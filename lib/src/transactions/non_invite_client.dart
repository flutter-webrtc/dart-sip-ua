import '../../sip_ua.dart';
import '../sip_message.dart';
import '../timers.dart';
import '../transport.dart';
import '../ua.dart';
import '../utils.dart';
import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../logger.dart';
import 'transaction_base.dart';

final logger = new Log();

class NonInviteClientTransaction extends TransactionBase {
  EventManager eventHandlers;
  var F, K;

  NonInviteClientTransaction(
      UA ua, Transport transport, request, eventHandlers) {
    this.id = 'z9hG4bK${Math.floor(Math.random())}';
    this.ua = ua;
    this.transport = transport;
    this.request = request;
    this.eventHandlers = eventHandlers;

    var via = 'SIP/2.0/${transport.via_transport}';

    via += ' ${ua.configuration.via_host};branch=${this.id}';

    this.request.setHeader('via', via);

    this.ua.newTransaction(this);
  }

  stateChanged(state) {
    this.state = state;
    this.emit(EventStateChanged());
  }

  send() {
    this.stateChanged(TransactionState.TRYING);
    this.F = setTimeout(() {
      this.timer_F();
    }, Timers.TIMER_F);

    if (!this.transport.send(this.request)) {
      this.onTransportError();
    }
  }

  onTransportError() {
    logger.debug('transport error occurred, deleting transaction ${this.id}');
    clearTimeout(this.F);
    clearTimeout(this.K);
    this.stateChanged(TransactionState.TERMINATED);
    this.ua.destroyTransaction(this);
    this.eventHandlers.emit(EventOnTransportError());
  }

  timer_F() {
    logger.debug('Timer F expired for transaction ${this.id}');
    this.stateChanged(TransactionState.TERMINATED);
    this.ua.destroyTransaction(this);
    this.eventHandlers.emit(EventOnRequestTimeout());
  }

  timer_K() {
    this.stateChanged(TransactionState.TERMINATED);
    this.ua.destroyTransaction(this);
  }

  void receiveResponse(int status_code, IncomingMessage response,
      [void Function() onSuccess, void Function() onFailure]) {
    if (status_code < 200) {
      switch (this.state) {
        case TransactionState.TRYING:
        case TransactionState.PROCEEDING:
          this.stateChanged(TransactionState.PROCEEDING);
          this.eventHandlers.emit(EventOnReceiveResponse(response: response));
          break;
        default:
          break;
      }
    } else {
      switch (this.state) {
        case TransactionState.TRYING:
        case TransactionState.PROCEEDING:
          this.stateChanged(TransactionState.COMPLETED);
          clearTimeout(this.F);

          if (status_code == 408) {
            this.eventHandlers.emit(EventOnRequestTimeout());
          } else {
            this.eventHandlers.emit(EventOnReceiveResponse(response: response));
          }

          this.K = setTimeout(() {
            this.timer_K();
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
