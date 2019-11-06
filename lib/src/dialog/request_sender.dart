import '../../sip_ua.dart';
import '../constants.dart';
import '../dialog.dart';
import '../rtc_session.dart' as RTCSession;
import '../request_sender.dart';
import '../sip_message.dart';
import '../timers.dart';
import '../ua.dart';
import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../transactions/transaction_base.dart';

class DialogRequestSender {
  Dialog _dialog;
  UA _ua;
  OutgoingRequest _request;
  EventManager _eventHandlers;
  var _reattempt;
  var _reattemptTimer;
  var _request_sender;

  DialogRequestSender(
      Dialog dialog, OutgoingRequest request, EventManager eventHandlers) {
    this._dialog = dialog;
    this._ua = dialog.ua;
    this._request = request;
    this._eventHandlers = eventHandlers;

    // RFC3261 14.1 Modifying an Existing Session. UAC Behavior.
    this._reattempt = false;
    this._reattemptTimer = null;
  }

  OutgoingRequest get request => this._request;

  send() {
    EventManager localEventHandlers = EventManager();
    localEventHandlers.on(EventOnRequestTimeout(),
        (EventOnRequestTimeout value) {
      this._eventHandlers.emit(EventOnRequestTimeout());
    });
    localEventHandlers.on(EventOnTransportError(),
        (EventOnTransportError value) {
      this._eventHandlers.emit(EventOnTransportError());
    });
    localEventHandlers.on(EventOnAuthenticated(), (EventOnAuthenticated event) {
      this._eventHandlers.emit(EventOnAuthenticated(request: event.request));
    });
    localEventHandlers.on(EventOnReceiveResponse(),
        (EventOnReceiveResponse event) {
      this._receiveResponse(event.response);
    });

    var request_sender =
        new RequestSender(this._ua, this._request, localEventHandlers);

    request_sender.send();

    // RFC3261 14.2 Modifying an Existing Session -UAC BEHAVIOR-.
    if ((this._request.method == SipMethod.INVITE ||
            (this._request.method == SipMethod.UPDATE &&
                this._request.body != null)) &&
        request_sender.clientTransaction.state != TransactionState.TERMINATED) {
      this._dialog.uac_pending_reply = true;
      EventManager eventHandlers = request_sender.clientTransaction;
      void Function(EventStateChanged data) stateChanged;
      stateChanged = (EventStateChanged data) {
        if (request_sender.clientTransaction.state ==
                TransactionState.ACCEPTED ||
            request_sender.clientTransaction.state ==
                TransactionState.COMPLETED ||
            request_sender.clientTransaction.state ==
                TransactionState.TERMINATED) {
          eventHandlers.remove(EventStateChanged(), stateChanged);
          this._dialog.uac_pending_reply = false;
        }
      };

      eventHandlers.on(EventStateChanged(), stateChanged);
    }
  }

  _receiveResponse(response) {
    // RFC3261 12.2.1.2 408 or 481 is received for a request within a dialog.
    if (response.status_code == 408 || response.status_code == 481) {
      this._eventHandlers.emit(EventOnDialogError(response: response));
    } else if (response.method == SipMethod.INVITE &&
        response.status_code == 491) {
      if (this._reattempt != null) {
        if (response.status_code >= 200 && response.status_code < 300) {
          this._eventHandlers.emit(EventOnSuccessResponse(response: response));
        } else if (response.status_code >= 300) {
          this._eventHandlers.emit(EventOnErrorResponse(response: response));
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
      this._eventHandlers.emit(EventOnSuccessResponse(response: response));
    } else if (response.status_code >= 300) {
      this._eventHandlers.emit(EventOnErrorResponse(response: response));
    }
  }
}
