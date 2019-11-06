import 'package:sip_ua/src/sip_message.dart';

import '../../sip_ua.dart';
import '../timers.dart';
import '../transport.dart';
import '../ua.dart';
import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../logger.dart';
import 'transaction_base.dart';

final logger = new Log();

class NonInviteServerTransaction extends TransactionBase {
  var transportError;
  var J;

  NonInviteServerTransaction(UA ua, Transport transport, request) {
    this.id = request.via_branch;
    this.ua = ua;
    this.transport = transport;
    this.request = request;
    this.last_response = IncomingMessage();
    request.server_transaction = this;

    this.state = TransactionState.TRYING;

    ua.newTransaction(this);
  }

  stateChanged(state) {
    this.state = state;
    this.emit(EventStateChanged());
  }

  timer_J() {
    logger.debug('Timer J expired for transaction ${this.id}');
    this.stateChanged(TransactionState.TERMINATED);
    this.ua.destroyTransaction(this);
  }

  onTransportError() {
    if (this.transportError == null) {
      this.transportError = true;

      logger.debug('transport error occurred, deleting transaction ${this.id}');

      clearTimeout(this.J);
      this.stateChanged(TransactionState.TERMINATED);
      this.ua.destroyTransaction(this);
    }
  }

  receiveResponse(int status_code, IncomingMessage response,
      [void Function() onSuccess, void Function() onFailure]) {
    if (status_code == 100) {
      /* RFC 4320 4.1
       * 'A SIP element MUST NOT
       * send any provisional response with a
       * Status-Code other than 100 to a non-INVITE request.'
       */
      switch (this.state) {
        case TransactionState.TRYING:
          this.stateChanged(TransactionState.PROCEEDING);
          if (!this.transport.send(response)) {
            this.onTransportError();
          }
          break;
        case TransactionState.PROCEEDING:
          this.last_response = response;
          if (!this.transport.send(response)) {
            this.onTransportError();
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
      switch (this.state) {
        case TransactionState.TRYING:
        case TransactionState.PROCEEDING:
          this.stateChanged(TransactionState.COMPLETED);
          this.last_response = response;
          this.J = setTimeout(() {
            this.timer_J();
          }, Timers.TIMER_J);
          if (!this.transport.send(response)) {
            this.onTransportError();
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
    throw Exception("Not Implemented");
  }
}
