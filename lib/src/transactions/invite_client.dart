import '../../sip_ua.dart';
import '../Constants.dart';
import '../SIPMessage.dart' as SIPMessage;
import '../Timers.dart';
import '../Transport.dart';
import '../Utils.dart';
import 'transaction_base.dart';


final ict_logger = new Logger('InviteClientTransaction');
debugict(msg) => ict_logger.debug(msg);

class InviteClientTransaction extends TransactionBase {
  var eventHandlers;

  var B, D, M;

  InviteClientTransaction(UA ua, Transport transport, request, eventHandlers) {
    this.id = 'z9hG4bK${Math.floor(Math.random() * 10000000)}';
    this.ua = ua;
    this.transport = transport;
    this.request = request;
    this.eventHandlers = eventHandlers;
    request.transaction = this;

    var via = 'SIP/2.0/${transport.via_transport}';

    via += ' ${ua.configuration.via_host};branch=${this.id}';

    this.request.setHeader('via', via);

    this.ua.newTransaction(this);
  }

  stateChanged(TransactionState state) {
    this.state = state;
    this.emit('stateChanged');
  }

  send() {
    this.stateChanged(TransactionState.CALLING);
    this.B = setTimeout(() {
      this.timer_B();
    }, Timers.TIMER_B);

    if (!this.transport.send(this.request)) {
      this.onTransportError();
    }
  }

  onTransportError() {
    clearTimeout(this.B);
    clearTimeout(this.D);
    clearTimeout(this.M);

    if (this.state != TransactionState.ACCEPTED) {
      debugict('transport error occurred, deleting transaction ${this.id}');
      this.eventHandlers['onTransportError']();
    }

    this.stateChanged(TransactionState.TERMINATED);
    this.ua.destroyTransaction(this);
  }

  // RFC 6026 7.2.
  timer_M() {
    debugict('Timer M expired for transaction ${this.id}');

    if (this.state == TransactionState.ACCEPTED) {
      clearTimeout(this.B);
      this.stateChanged(TransactionState.TERMINATED);
      this.ua.destroyTransaction(this);
    }
  }

  // RFC 3261 17.1.1.
  timer_B() {
    debugict('Timer B expired for transaction ${this.id}');
    if (this.state == TransactionState.CALLING) {
      this.stateChanged(TransactionState.TERMINATED);
      this.ua.destroyTransaction(this);
      this.eventHandlers['onRequestTimeout']();
    }
  }

  timer_D() {
    debugict('Timer D expired for transaction ${this.id}');
    clearTimeout(this.B);
    this.stateChanged(TransactionState.TERMINATED);
    this.ua.destroyTransaction(this);
  }

  sendACK(response) {
    var ack = new SIPMessage.OutgoingRequest(
        SipMethod.ACK, this.request.ruri, this.ua, {
      'route_set': this.request.getHeaders('route'),
      'call_id': this.request.getHeader('call-id'),
      'cseq': this.request.cseq
    });

    ack.setHeader('from', this.request.getHeader('from'));
    ack.setHeader('via', this.request.getHeader('via'));
    ack.setHeader('to', response.getHeader('to'));

    this.D = setTimeout(() {
      this.timer_D();
    }, Timers.TIMER_D);

    this.transport.send(ack);
  }

  cancel(reason) {
    // Send only if a provisional response (>100) has been received.
    if (this.state != TransactionState.PROCEEDING) {
      return;
    }

    var cancel = new SIPMessage.OutgoingRequest(
        SipMethod.CANCEL, this.request.ruri, this.ua, {
      'route_set': this.request.getHeaders('route'),
      'call_id': this.request.getHeader('call-id'),
      'cseq': this.request.cseq
    });

    cancel.setHeader('from', this.request.getHeader('from'));
    cancel.setHeader('via', this.request.getHeader('via'));
    cancel.setHeader('to', this.request.getHeader('to'));

    if (reason != null) {
      cancel.setHeader('reason', reason);
    }

    this.transport.send(cancel);
  }

  receiveResponse(SIPMessage.IncomingMessage response) {
    var status_code = response.status_code;

    if (status_code >= 100 && status_code <= 199) {
      switch (this.state) {
        case TransactionState.CALLING:
          this.stateChanged(TransactionState.PROCEEDING);
          this.eventHandlers['onReceiveResponse'](response);
          break;
        case TransactionState.PROCEEDING:
          this.eventHandlers['onReceiveResponse'](response);
          break;
        default:
          break;
      }
    } else if (status_code >= 200 && status_code <= 299) {
      switch (this.state) {
        case TransactionState.CALLING:
        case TransactionState.PROCEEDING:
          this.stateChanged(TransactionState.ACCEPTED);
          this.M = setTimeout(() {
            this.timer_M();
          }, Timers.TIMER_M);
          this.eventHandlers['onReceiveResponse'](response);
          break;
        case TransactionState.ACCEPTED:
          this.eventHandlers['onReceiveResponse'](response);
          break;
        default:
          break;
      }
    } else if (status_code >= 300 && status_code <= 699) {
      switch (this.state) {
        case TransactionState.CALLING:
        case TransactionState.PROCEEDING:
          this.stateChanged(TransactionState.COMPLETED);
          this.sendACK(response);
          this.eventHandlers['onReceiveResponse'](response);
          break;
        case TransactionState.COMPLETED:
          this.sendACK(response);
          break;
        default:
          break;
      }
    }
  }
}

