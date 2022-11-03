import 'dart:async';

import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../logger.dart';
import '../sip_message.dart';
import '../timers.dart';
import '../transport.dart';
import '../ua.dart';
import '../utils.dart';
import 'transaction_base.dart';

class NonInviteClientTransaction extends TransactionBase {
  NonInviteClientTransaction(UA ua, Transport transport,
      OutgoingRequest request, EventManager eventHandlers) {
    id = 'z9hG4bK${Math.random().floor()}';
    this.ua = ua;
    this.transport = transport;
    this.request = request;
    _eventHandlers = eventHandlers;

    String via = 'SIP/2.0/${transport.via_transport}';

    via += ' ${ua.configuration.via_host};branch=$id';

    request.setHeader('via', via);

    ua.newTransaction(this);
  }

  late EventManager _eventHandlers;
  Timer? F, K;

  void stateChanged(TransactionState state) {
    this.state = state;
    emit(EventStateChanged());
  }

  @override
  void send() {
    stateChanged(TransactionState.TRYING);
    F = setTimeout(() {
      timer_F();
    }, Timers.TIMER_F);

    if (!transport!.send(request)) {
      onTransportError();
    }
  }

  @override
  void onTransportError() {
    logger.d('transport error occurred, deleting transaction $id');
    clearTimeout(F);
    clearTimeout(K);
    stateChanged(TransactionState.TERMINATED);
    ua.destroyTransaction(this);
    _eventHandlers.emit(EventOnTransportError());
  }

  void timer_F() {
    logger.d('Timer F expired for transaction $id');
    stateChanged(TransactionState.TERMINATED);
    ua.destroyTransaction(this);
    _eventHandlers.emit(EventOnRequestTimeout());
  }

  void timer_K() {
    stateChanged(TransactionState.TERMINATED);
    ua.destroyTransaction(this);
  }

  @override
  void receiveResponse(int status_code, IncomingMessage response,
      [void Function()? onSuccess, void Function()? onFailure]) {
    if (status_code < 200) {
      switch (state) {
        case TransactionState.TRYING:
        case TransactionState.PROCEEDING:
          stateChanged(TransactionState.PROCEEDING);
          _eventHandlers.emit(
              EventOnReceiveResponse(response: response as IncomingResponse?));
          break;
        default:
          break;
      }
    } else {
      switch (state) {
        case TransactionState.TRYING:
        case TransactionState.PROCEEDING:
          stateChanged(TransactionState.COMPLETED);
          clearTimeout(F);

          if (status_code == 408) {
            _eventHandlers.emit(EventOnRequestTimeout());
          } else {
            _eventHandlers.emit(EventOnReceiveResponse(
                response: response as IncomingResponse?));
          }

          K = setTimeout(() {
            timer_K();
          }, Timers.TIMER_K);
          break;
        case TransactionState.COMPLETED:
          break;
        default:
          break;
      }
    }
  }
}
