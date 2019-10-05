import 'package:sip_ua/sip_ua.dart';
import 'package:sip_ua/src/Timers.dart';
import 'package:sip_ua/src/Transport.dart';
import 'package:sip_ua/src/Utils.dart';
import 'package:sip_ua/src/transactions/Transactions.dart';
import 'package:sip_ua/src/transactions/transaction_base.dart';

import '../SIPMessage.dart' as SIPMessage;

final nict_logger = new Logger('NonInviteClientTransaction');
debugnict(msg) => nict_logger.debug(msg);

class NonInviteClientTransaction extends TransactionBase {
  var eventHandlers;
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
    this.emit('stateChanged');
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
    debugnict('transport error occurred, deleting transaction ${this.id}');
    clearTimeout(this.F);
    clearTimeout(this.K);
    this.stateChanged(TransactionState.TERMINATED);
    this.ua.destroyTransaction(this);
    this.eventHandlers['onTransportError']();
  }

  timer_F() {
    debugnict('Timer F expired for transaction ${this.id}');
    this.stateChanged(TransactionState.TERMINATED);
    this.ua.destroyTransaction(this);
    this.eventHandlers['onRequestTimeout']();
  }

  timer_K() {
    this.stateChanged(TransactionState.TERMINATED);
    this.ua.destroyTransaction(this);
  }

  receiveResponse(SIPMessage.IncomingResponse response) {
    var status_code = response.status_code;

    if (status_code < 200) {
      switch (this.state) {
        case TransactionState.TRYING:
        case TransactionState.PROCEEDING:
          this.stateChanged(TransactionState.PROCEEDING);
          this.eventHandlers['onReceiveResponse'](response);
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
            this.eventHandlers['onRequestTimeout']();
          } else {
            this.eventHandlers['onReceiveResponse'](response);
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
