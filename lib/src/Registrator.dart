import 'Constants.dart';
import 'Utils.dart' as Utils;
import 'Timers.dart';
import 'Constants.dart' as DartSIP_C;
import 'SIPMessage.dart' as SIPMessage;
import 'RequestSender.dart';
import 'logger.dart';

const MIN_REGISTER_EXPIRES = 10; // In seconds.

class Registrator {
  var _ua;
  var _transport;
  var _registrar;
  var _expires;
  var _call_id;
  var _cseq;
  var _to_uri;
  var _registrationTimer;
  var _registering;
  var _registered;
  var _contact;
  var _extraHeaders;
  var _extraContactParams;
  final logger = Logger('Registrator');
  debug(msg) => logger.debug(msg);
  debugerror(error) => logger.error(error);

  Registrator(ua, [transport]) {
    var reg_id = 1; // Force reg_id to 1.

    this._ua = ua;
    this._transport = transport;

    this._registrar = ua.configuration.registrar_server;
    this._expires = ua.configuration.register_expires;

    // Call-ID and CSeq values RFC3261 10.2.
    this._call_id = Utils.createRandomToken(22);
    this._cseq = 0;

    this._to_uri = ua.configuration.uri;

    this._registrationTimer = null;

    // Ongoing Register request.
    this._registering = false;

    // Set status.
    this._registered = false;

    // Contact header.
    this._contact = this._ua.contact.toString();

    // Sip.ice media feature tag (RFC 5768).
    this._contact += ';+sip.ice';

    // Custom headers for REGISTER and un-REGISTER.
    this._extraHeaders = [];

    // Custom Contact header params for REGISTER and un-REGISTER.
    this._extraContactParams = '';

    if (reg_id != null) {
      this._contact += ';reg-id=${reg_id}';
      this._contact +=
          ';+sip.instance="<urn:uuid:${this._ua.configuration.instance_id}>"';
    }
  }

  get registered => this._registered;

  get transport => this._transport;

  setExtraHeaders(extraHeaders) {
    if (extraHeaders is! List) {
      extraHeaders = [];
    }
    this._extraHeaders = extraHeaders;
  }

  setExtraContactParams(extraContactParams) {
    if (extraContactParams is! Map) {
      extraContactParams = {};
    }

    // Reset it.
    this._extraContactParams = '';

    extraContactParams.forEach((param_key, param_value) {
      this._extraContactParams += (';${param_key}');
      if (param_value != null) {
        this._extraContactParams += ('=${param_value}');
      }
    });
  }

  register() {
    if (this._registering) {
      debug('Register request in progress...');
      return;
    }

    var extraHeaders = [];

    extraHeaders.add(
        'Contact: ${this._contact};expires=${this._expires}${this._extraContactParams}');
    extraHeaders.add('Expires: ${this._expires}');

    print(this._contact);

    var request = new SIPMessage.OutgoingRequest(
        SipMethod.REGISTER,
        this._registrar,
        this._ua,
        {
          'to_uri': this._to_uri,
          'call_id': this._call_id,
          'cseq': (this._cseq += 1)
        },
        extraHeaders);

    var request_sender = new RequestSender(this._ua, request, {
      'onRequestTimeout': () {
        this._registrationFailure(null, DartSIP_C.causes.REQUEST_TIMEOUT);
      },
      'onTransportError': () {
        this._registrationFailure(null, DartSIP_C.causes.CONNECTION_ERROR);
      },
      // Increase the CSeq on authentication.
      'onAuthenticated': (request) {
        this._cseq += 1;
      },
      'onReceiveResponse': (response) {
        // Discard responses to older REGISTER/un-REGISTER requests.
        if (response.cseq != this._cseq) {
          return;
        }

        // Clear registration timer.
        if (this._registrationTimer != null) {
          clearTimeout(this._registrationTimer);
          this._registrationTimer = null;
        }

        String status_code = response.status_code.toString();

        if (Utils.test1XX(status_code)) {
          // Ignore provisional responses.
        } else if (Utils.test2XX(status_code)) {
          this._registering = false;

          if (!response.hasHeader('Contact')) {
            debug(
                'no Contact header in response to REGISTER, response ignored');
            return;
          }

          var contacts = [];
          response.headers['Contact'].forEach((item) {
            contacts.add(item['parsed']);
          });
          // Get the Contact pointing to us and update the expires value accordingly.
          var contact = contacts.firstWhere(
              (element) => (element.uri.user == this._ua.contact.uri.user));

          if (contact == null) {
            debug('no Contact header pointing to us, response ignored');
            return;
          }

          var expires = contact.getParam('expires');

          if (expires == null && response.hasHeader('expires')) {
            expires = response.getHeader('expires');
          }

          if (expires == null) {
            expires = this._expires;
          }

          expires = num.tryParse(expires) ?? 0;

          if (expires < MIN_REGISTER_EXPIRES) expires = MIN_REGISTER_EXPIRES;

          // Re-Register or emit an event before the expiration interval has elapsed.
          // For that, decrease the expires value. ie: 3 seconds.
          this._registrationTimer = setTimeout(() {
            clearTimeout(this._registrationTimer);
            this._registrationTimer = null;
            // If there are no listeners for registrationExpiring, renew registration.
            // If there are listeners, var the listening do the register call.
            if (this._ua.listeners('registrationExpiring').length == 0) {
              this.register();
            } else {
              this._ua.emit('registrationExpiring');
            }
          }, (expires * 1000) - 5000);

          // Save gruu values.
          if (contact.hasParam('temp-gruu')) {
            this._ua.contact.temp_gruu =
                contact.getParam('temp-gruu').replaceAll('"', '');
          }
          if (contact.hasParam('pub-gruu')) {
            this._ua.contact.pub_gruu =
                contact.getParam('pub-gruu').replaceAll('"', '');
          }

          if (!this._registered) {
            this._registered = true;
            this._ua.registered({'response': response});
          }
        } else
        // Interval too brief RFC3261 10.2.8.
        if (status_code.contains(new RegExp(r'^423$'))) {
          if (response.hasHeader('min-expires')) {
            // Increase our registration interval to the suggested minimum.
            this._expires =
                num.tryParse(response.getHeader('min-expires')) ?? 0;

            if (this._expires < MIN_REGISTER_EXPIRES)
              this._expires = MIN_REGISTER_EXPIRES;

            // Attempt the registration again immediately.
            this.register();
          } else {
            // This response MUST contain a Min-Expires header field.
            debug('423 response received for REGISTER without Min-Expires');

            this._registrationFailure(
                response, DartSIP_C.causes.SIP_FAILURE_CODE);
          }
        } else {
          var cause = Utils.sipErrorCause(response.status_code);
          this._registrationFailure(response, cause);
        }
      }
    });

    this._registering = true;
    request_sender.send();
  }

  unregister(unregister_all) {
    if (this._registered == null) {
      debug('already unregistered');

      return;
    }

    this._registered = false;

    // Clear the registration timer.
    if (this._registrationTimer != null) {
      clearTimeout(this._registrationTimer);
      this._registrationTimer = null;
    }

    var extraHeaders = [];

    if (unregister_all) {
      extraHeaders.add('Contact: *${this._extraContactParams}');
    } else {
      extraHeaders.add(
          'Contact: ${this._contact};expires=0${this._extraContactParams}');
    }

    extraHeaders.add('Expires: 0');

    var request = new SIPMessage.OutgoingRequest(
        SipMethod.REGISTER,
        this._registrar,
        this._ua,
        {
          'to_uri': this._to_uri,
          'call_id': this._call_id,
          'cseq': (this._cseq += 1)
        },
        extraHeaders);

    var request_sender = new RequestSender(this._ua, request, {
      'onRequestTimeout': () {
        this._unregistered(null, DartSIP_C.causes.REQUEST_TIMEOUT);
      },
      'onTransportError': () {
        this._unregistered(null, DartSIP_C.causes.CONNECTION_ERROR);
      },
      // Increase the CSeq on authentication.
      'onAuthenticated': (request) {
        this._cseq += 1;
      },
      'onReceiveResponse': (response) {
        String status_code = response.status_code.toString();
        if (Utils.test2XX(status_code)) {
          this._unregistered(response);
        } else if (Utils.test1XX(status_code)) {
          // Ignore provisional responses.
        } else {
          var cause = Utils.sipErrorCause(response.status_code);
          this._unregistered(response, cause);
        }
      }
    });

    request_sender.send();
  }

  close() {
    if (this._registered) {
      this.unregister(false);
    }
  }

  onTransportClosed() {
    this._registering = false;
    if (this._registrationTimer != null) {
      clearTimeout(this._registrationTimer);
      this._registrationTimer = null;
    }

    if (this._registered) {
      this._registered = false;
      this._ua.unregistered(Map<String, dynamic>());
    }
  }

  _registrationFailure(response, cause) {
    this._registering = false;
    this._ua.registrationFailed({'response': response ?? null, 'cause': cause});

    if (this._registered) {
      this._registered = false;
      this._ua.unregistered({'response': response ?? null, 'cause': cause});
    }
  }

  _unregistered([response, cause]) {
    this._registering = false;
    this._registered = false;
    this
        ._ua
        .unregistered({'response': response ?? null, 'cause': cause ?? null});
  }
}
