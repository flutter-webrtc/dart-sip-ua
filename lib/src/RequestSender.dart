

import '../sip_ua.dart';
import 'Constants.dart';
import 'DigestAuthentication.dart';
import 'UA.dart' as UAC;
import 'logger.dart';
import 'transactions/ack_client.dart';
import 'transactions/invite_client.dart';
import 'transactions/non_invite_client.dart';
import 'transactions/transaction_base.dart';

// Default event handlers.
var EventHandlers = {
  'onRequestTimeout': () => {},
  'onTransportError': () => {},
  'onReceiveResponse': (response) => {},
  'onAuthenticated': (request) => {}
};

class RequestSender {
  UA _ua;
  var _eventHandlers;
  SipMethod _method;
  var _request;
  var _auth;
  var _challenged;
  var _staled;
  TransactionBase clientTransaction;
  final logger = new Logger('RequestSender');
  debug(msg) => logger.debug(msg);
  debugerror(error) => logger.error(error);

  RequestSender(UA ua, request, eventHandlers) {
    this._ua = ua;
    this._eventHandlers = eventHandlers;
    this._method = request.method;
    this._request = request;
    this._auth = null;
    this._challenged = false;
    this._staled = false;

    // Define the null handlers.
    EventHandlers.forEach((handler, fn) {
      if (this._eventHandlers[handler] == null) {
        this._eventHandlers[handler] = EventHandlers[handler];
      }
    });

    // If ua is in closing process or even closed just allow sending Bye and ACK.
    if (ua.status == UAC.C.STATUS_USER_CLOSED &&
        (this._method != SipMethod.BYE || this._method != SipMethod.ACK)) {
      this._eventHandlers['onTransportError']();
    }
  }

  /**
  * Create the client transaction and send the message.
  */
  send() {
    var eventHandlers = {
      'onRequestTimeout': () => {this._eventHandlers['onRequestTimeout']()},
      'onTransportError': () => {this._eventHandlers['onTransportError']()},
      'onAuthenticated': (request) =>
          {this._eventHandlers['onAuthenticated'](request)},
      'onReceiveResponse': (response) => {this._receiveResponse(response)}
    };

    switch (this._method) {
      case SipMethod.INVITE:
        this.clientTransaction = new InviteClientTransaction(
            this._ua, this._ua.transport, this._request, eventHandlers);
        break;
      case SipMethod.ACK:
        this.clientTransaction = new AckClientTransaction(
            this._ua, this._ua.transport, this._request, eventHandlers);
        break;
      default:
        this.clientTransaction =  new NonInviteClientTransaction(
            this._ua, this._ua.transport, this._request, eventHandlers);
    }

    this.clientTransaction.send();
  }

  /**
  * Called from client transaction when receiving a correct response to the request.
  * Authenticate request if needed or pass the response back to the applicant.
  */
  _receiveResponse(response) {
    var challenge;
    var authorization_header_name;
    var status_code = response.status_code;

    /*
    * Authentication
    * Authenticate once. _challenged_ flag used to avoid infinite authentications.
    */
    if ((status_code == 401 || status_code == 407) &&
        (this._ua.configuration.password != null ||
            this._ua.configuration.ha1 != null)) {
      // Get and parse the appropriate WWW-Authenticate or Proxy-Authenticate header.
      if (response.status_code == 401) {
        challenge = response.parseHeader('www-authenticate');
        authorization_header_name = 'authorization';
      } else {
        challenge = response.parseHeader('proxy-authenticate');
        authorization_header_name = 'proxy-authorization';
      }

      // Verify it seems a valid challenge.
      if (challenge == null) {
        debug(
            '${response.status_code} with wrong or missing challenge, cannot authenticate');
        this._eventHandlers['onReceiveResponse'](response);

        return;
      }

      if (!this._challenged || (!this._staled && challenge.stale == true)) {
        if (this._auth == null) {
          this._auth = new DigestAuthentication(Credentials.fromMap({
            'username': this._ua.configuration.authorization_user,
            'password': this._ua.configuration.password,
            'realm': this._ua.configuration.realm,
            'ha1': this._ua.configuration.ha1
          }));
        }

        // Verify that the challenge is really valid.
        if (!this._auth.authenticate(
            this._request.method,
            Challenge.fromMap({
              'algorithm': challenge.algorithm,
              'realm': challenge.realm,
              'nonce': challenge.nonce,
              'opaque': challenge.opaque,
              'stale': challenge.stale,
              'qop': challenge.qop,
            }),
            this._request.ruri
            )) {
          this._eventHandlers['onReceiveResponse'](response);
          return;
        }
        this._challenged = true;

        // Update ha1 and realm in the UA.
        this._ua.set('realm', this._auth.get('realm'));
        this._ua.set('ha1', this._auth.get('ha1'));

        if (challenge.stale != null) {
          this._staled = true;
        }

        this._request = this._request.clone();
        this._request.cseq += 1;
        this
            ._request
            .setHeader('cseq', '${this._request.cseq} ${SipMethodHelper.getName(this._method)}');
        this
            ._request
            .setHeader(authorization_header_name, this._auth.toString());

        this._eventHandlers['onAuthenticated'](this._request);
        this.send();
      } else {
        this._eventHandlers['onReceiveResponse'](response);
      }
    } else {
      this._eventHandlers['onReceiveResponse'](response);
    }
  }
}
