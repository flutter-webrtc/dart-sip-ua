import 'dart:async';

import '../constants.dart';
import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../logger.dart';
import '../sip_message.dart';
import '../socket_transport.dart';
import '../timers.dart';
import '../ua.dart';
import '../utils.dart';
import 'transaction_base.dart';

class InviteClientTransaction extends TransactionBase {
  InviteClientTransaction(UA ua, SocketTransport transport,
      OutgoingRequest request, EventManager eventHandlers) {
    id = 'z9hG4bK${(Math.random() * 10000000).floor()}';
    this.ua = ua;
    this.transport = transport;
    this.request = request;
    _eventHandlers = eventHandlers;
    request.transaction = this;

    String via = 'SIP/2.0/${transport.via_transport}';

    via += ' ${ua.configuration.via_host};branch=$id';

    this.request.setHeader('via', via);

    this.ua.newTransaction(this);
  }
  late EventManager _eventHandlers;

  Timer? B, D, M;

  void stateChanged(TransactionState state) {
    this.state = state;
    emit(EventStateChanged());
  }

  @override
  void send() {
    stateChanged(TransactionState.CALLING);
    B = setTimeout(() {
      timer_B();
    }, Timers.TIMER_B);

    if (!transport!.send(request)) {
      onTransportError();
    }
  }

  @override
  void onTransportError() {
    clearTimeout(B);
    clearTimeout(D);
    clearTimeout(M);

    if (state != TransactionState.ACCEPTED) {
      logger.d('transport error occurred, deleting transaction $id');
      _eventHandlers.emit(EventOnTransportError());
    }

    stateChanged(TransactionState.TERMINATED);
    ua.destroyTransaction(this);
  }

  // RFC 6026 7.2.
  void timer_M() {
    logger.d('Timer M expired for transaction $id');

    if (state == TransactionState.ACCEPTED) {
      clearTimeout(B);
      stateChanged(TransactionState.TERMINATED);
      ua.destroyTransaction(this);
    }
  }

  // RFC 3261 17.1.1.
  void timer_B() {
    logger.d('Timer B expired for transaction $id');
    if (state == TransactionState.CALLING) {
      stateChanged(TransactionState.TERMINATED);
      ua.destroyTransaction(this);
      _eventHandlers.emit(EventOnRequestTimeout());
    }
  }

  void timer_D() {
    logger.d('Timer D expired for transaction $id');
    clearTimeout(B);
    stateChanged(TransactionState.TERMINATED);
    ua.destroyTransaction(this);
  }

  void sendACK(IncomingMessage response) {
    OutgoingRequest ack =
        OutgoingRequest(SipMethod.ACK, request.ruri, ua, <String, dynamic>{
      'route_set': request.getHeaders('route'),
      'call_id': request.getHeader('call-id'),
      'cseq': request.cseq
    });

    ack.setHeader('from', request.getHeader('from'));
    ack.setHeader('via', request.getHeader('via'));
    ack.setHeader('to', response.getHeader('to'));

    D = setTimeout(() {
      timer_D();
    }, Timers.TIMER_D);

    transport!.send(ack);
  }

  void cancel(String? reason) {
    // Send only if a provisional response (>100) has been received.
    if (state != TransactionState.PROCEEDING) {
      return;
    }

    OutgoingRequest cancel =
        OutgoingRequest(SipMethod.CANCEL, request.ruri, ua, <String, dynamic>{
      'route_set': request.getHeaders('route'),
      'call_id': request.getHeader('call-id'),
      'cseq': request.cseq
    });

    cancel.setHeader('from', request.getHeader('from'));
    cancel.setHeader('via', request.getHeader('via'));
    cancel.setHeader('to', request.getHeader('to'));

    if (reason != null) {
      cancel.setHeader('reason', reason);
    }

    transport!.send(cancel);
  }

  @override
  void receiveResponse(int? status_code, IncomingMessage response,
      [void Function()? onSuccess, void Function()? onFailure]) {
    int status_code = response.status_code;

    if (status_code >= 100 && status_code <= 199) {
      switch (state) {
        case TransactionState.CALLING:
          stateChanged(TransactionState.PROCEEDING);
          _eventHandlers.emit(
              EventOnReceiveResponse(response: response as IncomingResponse?));
          break;
        case TransactionState.PROCEEDING:
          _eventHandlers.emit(
              EventOnReceiveResponse(response: response as IncomingResponse?));
          break;
        default:
          break;
      }
    } else if (status_code >= 200 && status_code <= 299) {
      switch (state) {
        case TransactionState.CALLING:
        case TransactionState.PROCEEDING:
          stateChanged(TransactionState.ACCEPTED);
          M = setTimeout(() {
            timer_M();
          }, Timers.TIMER_M);
          _eventHandlers.emit(
              EventOnReceiveResponse(response: response as IncomingResponse?));
          break;
        case TransactionState.ACCEPTED:
          _eventHandlers.emit(
              EventOnReceiveResponse(response: response as IncomingResponse?));
          break;
        default:
          break;
      }
    } else if (status_code >= 300 && status_code <= 699) {
      switch (state) {
        case TransactionState.CALLING:
        case TransactionState.PROCEEDING:
          stateChanged(TransactionState.COMPLETED);
          sendACK(response);
          _eventHandlers.emit(
              EventOnReceiveResponse(response: response as IncomingResponse?));
          break;
        case TransactionState.COMPLETED:
          sendACK(response);
          break;
        default:
          break;
      }
    }
  }
}
