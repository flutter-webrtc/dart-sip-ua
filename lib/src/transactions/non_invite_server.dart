import 'dart:async';

import 'package:sip_ua/src/sip_message.dart';
import '../event_manager/internal_events.dart';
import '../logger.dart';
import '../timers.dart';
import '../transport.dart';
import '../ua.dart';
import 'transaction_base.dart';

class NonInviteServerTransaction extends TransactionBase {
  NonInviteServerTransaction(
      UA ua, Transport? transport, IncomingRequest request) {
    id = request.via_branch;
    this.ua = ua;
    this.transport = transport;
    this.request = request;
    last_response = IncomingMessage();
    request.server_transaction = this;

    state = TransactionState.TRYING;

    ua.newTransaction(this);
  }
  bool? transportError;
  Timer? J;

  void stateChanged(TransactionState state) {
    this.state = state;
    emit(EventStateChanged());
  }

  void timer_J() {
    logger.d('Timer J expired for transaction $id');
    stateChanged(TransactionState.TERMINATED);
    ua.destroyTransaction(this);
  }

  @override
  void onTransportError() {
    if (transportError == null) {
      transportError = true;

      logger.d('transport error occurred, deleting transaction $id');

      clearTimeout(J);
      stateChanged(TransactionState.TERMINATED);
      ua.destroyTransaction(this);
    }
  }

  @override
  void receiveResponse(int status_code, IncomingMessage response,
      [void Function()? onSuccess, void Function()? onFailure]) {
    if (status_code == 100) {
      /* RFC 4320 4.1
       * 'A SIP element MUST NOT
       * send any provisional response with a
       * Status-Code other than 100 to a non-INVITE request.'
       */
      switch (state) {
        case TransactionState.TRYING:
          stateChanged(TransactionState.PROCEEDING);
          if (!transport!.send(response)) {
            onTransportError();
          }
          break;
        case TransactionState.PROCEEDING:
          last_response = response;
          if (!transport!.send(response)) {
            onTransportError();
            if (onFailure != null) {
              onFailure();
            }
          } else if (onSuccess != null) {
            onSuccess();
          }
          break;
        default:
          break;
      }
    } else if (status_code >= 200 && status_code <= 699) {
      switch (state) {
        case TransactionState.TRYING:
        case TransactionState.PROCEEDING:
          stateChanged(TransactionState.COMPLETED);
          last_response = response;
          J = setTimeout(() {
            timer_J();
          }, Timers.TIMER_J);
          if (!transport!.send(response)) {
            onTransportError();
            if (onFailure != null) {
              onFailure();
            }
          } else if (onSuccess != null) {
            onSuccess();
          }
          break;
        case TransactionState.COMPLETED:
          break;
        default:
          break;
      }
    }
  }

  @override
  void send() {
    throw Exception('Not Implemented');
  }
}
