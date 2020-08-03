import '../sip_ua.dart';
import 'constants.dart';
import 'constants.dart' as DartSIP_C;
import 'request_sender.dart';

import 'sip_message.dart';
import 'timers.dart';
import 'transport.dart';
import 'ua.dart';
import 'utils.dart' as Utils;
import 'event_manager/event_manager.dart';
import 'event_manager/internal_events.dart';
import 'logger.dart';

const MIN_REGISTER_EXPIRES = 10; // In seconds.

class UnHandledResponse {
  var status_code;
  var reason_phrase;
  UnHandledResponse(this.status_code, this.reason_phrase);
}

class Registrator {
  UA _ua;
  Transport _transport;
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
  final logger = Log();

  Registrator(UA ua, [Transport transport]) {
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
      logger.debug('Register request in progress...');
      return;
    }

    var extraHeaders = _extraHeaders ?? [];

    extraHeaders.add(
        'Contact: ${this._contact};expires=${this._expires}${this._extraContactParams}');
    extraHeaders.add('Expires: ${this._expires}');

    logger.warn(this._contact);

    var request = new OutgoingRequest(
        SipMethod.REGISTER,
        this._registrar,
        this._ua,
        {
          'to_uri': this._to_uri,
          'call_id': this._call_id,
          'cseq': (this._cseq += 1)
        },
        extraHeaders);

    EventManager localEventHandlers = EventManager();
    localEventHandlers.on(EventOnRequestTimeout(),
        (EventOnRequestTimeout value) {
      this._registrationFailure(UnHandledResponse(408, DartSIP_C.causes.REQUEST_TIMEOUT), DartSIP_C.causes.REQUEST_TIMEOUT);
    });
    localEventHandlers.on(EventOnTransportError(),
        (EventOnTransportError value) {
      this._registrationFailure(UnHandledResponse(500, DartSIP_C.causes.CONNECTION_ERROR), DartSIP_C.causes.CONNECTION_ERROR);
    });
    localEventHandlers.on(EventOnAuthenticated(), (EventOnAuthenticated value) {
      this._cseq += 1;
    });
    localEventHandlers.on(EventOnReceiveResponse(),
        (EventOnReceiveResponse event) {
      {
        // Discard responses to older REGISTER/un-REGISTER requests.
        if (event.response.cseq != this._cseq) {
          return;
        }

        // Clear registration timer.
        if (this._registrationTimer != null) {
          clearTimeout(this._registrationTimer);
          this._registrationTimer = null;
        }

        String status_code = event.response.status_code.toString();

        if (Utils.test1XX(status_code)) {
          // Ignore provisional responses.
        } else if (Utils.test2XX(status_code)) {
          this._registering = false;

          if (!event.response.hasHeader('Contact')) {
            logger.debug(
                'no Contact header in response to REGISTER, response ignored');
            return;
          }

          var contacts = [];
          event.response.headers['Contact'].forEach((item) {
            contacts.add(item['parsed']);
          });
          // Get the Contact pointing to us and update the expires value accordingly.
          var contact = contacts.firstWhere(
              (element) => (element.uri.user == this._ua.contact.uri.user));

          if (contact == null) {
            logger.debug('no Contact header pointing to us, response ignored');
            return;
          }

          var expires = contact.getParam('expires');

          if (expires == null && event.response.hasHeader('expires')) {
            expires = event.response.getHeader('expires');
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
            if (!this._ua.hasListeners(EventRegistrationExpiring())) {
              this.register();
            } else {
              this._ua.emit(EventRegistrationExpiring());
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
            this._ua.registered(response: event.response);
          }
        } else
        // Interval too brief RFC3261 10.2.8.
        if (status_code.contains(new RegExp(r'^423$'))) {
          if (event.response.hasHeader('min-expires')) {
            // Increase our registration interval to the suggested minimum.
            this._expires =
                num.tryParse(event.response.getHeader('min-expires')) ?? 0;

            if (this._expires < MIN_REGISTER_EXPIRES)
              this._expires = MIN_REGISTER_EXPIRES;

            // Attempt the registration again immediately.
            this.register();
          } else {
            // This response MUST contain a Min-Expires header field.
            logger.debug(
                '423 response received for REGISTER without Min-Expires');

            this._registrationFailure(
                event.response, DartSIP_C.causes.SIP_FAILURE_CODE);
          }
        } else {
          var cause = Utils.sipErrorCause(event.response.status_code);
          this._registrationFailure(event.response, cause);
        }
      }
    });

    var request_sender =
        new RequestSender(this._ua, request, localEventHandlers);

    this._registering = true;
    request_sender.send();
  }

  unregister(unregister_all) {
    if (this._registered == null) {
      logger.debug('already unregistered');

      return;
    }

    this._registered = false;

    // Clear the registration timer.
    if (this._registrationTimer != null) {
      clearTimeout(this._registrationTimer);
      this._registrationTimer = null;
    }

    var extraHeaders = _extraHeaders ?? [];

    if (unregister_all) {
      extraHeaders.add('Contact: *${this._extraContactParams}');
    } else {
      extraHeaders.add(
          'Contact: ${this._contact};expires=0${this._extraContactParams}');
    }

    extraHeaders.add('Expires: 0');

    var request = new OutgoingRequest(
        SipMethod.REGISTER,
        this._registrar,
        this._ua,
        {
          'to_uri': this._to_uri,
          'call_id': this._call_id,
          'cseq': (this._cseq += 1)
        },
        extraHeaders);

    EventManager localEventHandlers = EventManager();
    localEventHandlers.on(EventOnRequestTimeout(),
        (EventOnRequestTimeout value) {
      this._unregistered(null, DartSIP_C.causes.REQUEST_TIMEOUT);
    });
    localEventHandlers.on(EventOnTransportError(),
        (EventOnTransportError value) {
      this._unregistered(null, DartSIP_C.causes.CONNECTION_ERROR);
    });
    localEventHandlers.on(EventOnAuthenticated(),
        (EventOnAuthenticated response) {
      // Increase the CSeq on authentication.

      this._cseq += 1;
    });
    localEventHandlers.on(EventOnReceiveResponse(),
        (EventOnReceiveResponse event) {
      String status_code = event.response.status_code.toString();
      if (Utils.test2XX(status_code)) {
        this._unregistered(event.response);
      } else if (Utils.test1XX(status_code)) {
        // Ignore provisional responses.
      } else {
        var cause = Utils.sipErrorCause(event.response.status_code);
        this._unregistered(event.response, cause);
      }
    });

    var request_sender =
        new RequestSender(this._ua, request, localEventHandlers);

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
      this._ua.unregistered();
    }
  }

  _registrationFailure(response, cause) {
    this._registering = false;
    this._ua.registrationFailed(response: response, cause: cause);

    if (this._registered) {
      this._registered = false;
      this._ua.unregistered(response: response, cause: cause);
    }
  }

  _unregistered([response, cause]) {
    this._registering = false;
    this._registered = false;
    this._ua.unregistered(response: response, cause: cause);
  }
}
