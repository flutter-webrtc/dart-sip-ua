import '../../sip_ua.dart';
import '../Constants.dart';
import '../Dialog.dart';
import '../RTCSession.dart' as RTCSession;
import '../RequestSender.dart';
import '../SIPMessage.dart';
import '../Timers.dart';
import '../transactions/transaction_base.dart';

// Default event handlers.
var EventHandlers = {
  'onRequestTimeout': () => {},
  'onTransportError': () => {},
  'onSuccessResponse': (response) => {},
  'onErrorResponse': (response) => {},
  'onAuthenticated': (request) => {},
  'onDialogError': () => {}
};

class DialogRequestSender {
  Dialog _dialog;
  UA _ua;
  OutgoingRequest _request;
  var _eventHandlers;
  var _reattempt;
  var _reattemptTimer;
  var _request_sender;

  DialogRequestSender(Dialog dialog, OutgoingRequest request, eventHandlers) {
    this._dialog = dialog;
    this._ua = dialog.ua;
    this._request = request;
    this._eventHandlers = eventHandlers;

    // RFC3261 14.1 Modifying an Existing Session. UAC Behavior.
    this._reattempt = false;
    this._reattemptTimer = null;

    // Define the null handlers.
    EventHandlers.forEach((handler, fn) {
      if (EventHandlers.containsKey(handler)) {
        if (this._eventHandlers[handler] == null) {
          this._eventHandlers[handler] = EventHandlers[handler];
        }
      }
    });
  }

  OutgoingRequest get request => this._request;

  send() {
    var request_sender = new RequestSender(this._ua, this._request, {
      'onRequestTimeout': () => {this._eventHandlers['onRequestTimeout']()},
      'onTransportError': () => {this._eventHandlers['onTransportError']()},
      'onAuthenticated': (request) =>
          {this._eventHandlers['onAuthenticated'](request)},
      'onReceiveResponse': (response) => {this._receiveResponse(response)}
    });

    request_sender.send();

    // RFC3261 14.2 Modifying an Existing Session -UAC BEHAVIOR-.
    if ((this._request.method == SipMethod.INVITE ||
            (this._request.method == SipMethod.UPDATE && this._request.body != null)) &&
        request_sender.clientTransaction.state !=
            TransactionState.TERMINATED) {
      this._dialog.uac_pending_reply = true;

      var stateChanged;
      stateChanged = () {
        if (request_sender.clientTransaction.state ==
                TransactionState.ACCEPTED ||
            request_sender.clientTransaction.state ==
                TransactionState.COMPLETED ||
            request_sender.clientTransaction.state ==
                TransactionState.TERMINATED) {
          request_sender.clientTransaction.remove('stateChanged', stateChanged);
          this._dialog.uac_pending_reply = false;
        }
      };

      request_sender.clientTransaction.on('stateChanged', stateChanged);
    }
  }

  _receiveResponse(response) {
    // RFC3261 12.2.1.2 408 or 481 is received for a request within a dialog.
    if (response.status_code == 408 || response.status_code == 481) {
      this._eventHandlers['onDialogError'](response);
    } else if (response.method == SipMethod.INVITE &&
        response.status_code == 491) {
      if (this._reattempt != null) {
        if (response.status_code >= 200 && response.status_code < 300) {
          this._eventHandlers['onSuccessResponse'](response);
        } else if (response.status_code >= 300) {
          this._eventHandlers['onErrorResponse'](response);
        }
      } else {
        this._request.cseq.value = this._dialog.local_seqnum += 1;
        this._reattemptTimer = setTimeout(() {
          // TODO: look at dialog state instead.
          if (this._dialog.owner.status != RTCSession.C.STATUS_TERMINATED) {
            this._reattempt = true;
            this._request_sender.send();
          }
        }, 1000);
      }
    } else if (response.status_code >= 200 && response.status_code < 300) {
      this._eventHandlers['onSuccessResponse'](response);
    } else if (response.status_code >= 300) {
      this._eventHandlers['onErrorResponse'](response);
    }
  }
}
