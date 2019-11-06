import '../../sip_ua.dart';
import '../sip_message.dart';
import '../timers.dart';
import '../transport.dart';
import '../ua.dart';
import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../logger.dart';
import 'transaction_base.dart';

final logger = new Log();

class InviteServerTransaction extends TransactionBase {
  var resendProvisionalTimer;
  var transportError;
  var L, H, I;

  InviteServerTransaction(UA ua, Transport transport, request) {
    this.id = request.via_branch;
    this.ua = ua;
    this.transport = transport;
    this.request = request;
    this.last_response = IncomingMessage();
    request.server_transaction = this;

    this.state = TransactionState.PROCEEDING;

    ua.newTransaction(this);

    this.resendProvisionalTimer = null;

    request.reply(100);
  }

  stateChanged(state) {
    this.state = state;
    this.emit(EventStateChanged());
  }

  timer_H() {
    logger.debug('Timer H expired for transaction ${this.id}');

    if (this.state == TransactionState.COMPLETED) {
      logger.debug('ACK not received, dialog will be terminated');
    }

    this.stateChanged(TransactionState.TERMINATED);
    this.ua.destroyTransaction(this);
  }

  timer_I() {
    this.stateChanged(TransactionState.TERMINATED);
  }

  // RFC 6026 7.1.
  timer_L() {
    logger.debug('Timer L expired for transaction ${this.id}');

    if (this.state == TransactionState.ACCEPTED) {
      this.stateChanged(TransactionState.TERMINATED);
      this.ua.destroyTransaction(this);
    }
  }

  onTransportError() {
    if (this.transportError == null) {
      this.transportError = true;

      logger.debug('transport error occurred, deleting transaction ${this.id}');

      if (this.resendProvisionalTimer != null) {
        clearInterval(this.resendProvisionalTimer);
        this.resendProvisionalTimer = null;
      }

      clearTimeout(this.L);
      clearTimeout(this.H);
      clearTimeout(this.I);

      this.stateChanged(TransactionState.TERMINATED);
      this.ua.destroyTransaction(this);
    }
  }

  resend_provisional() {
    if (!this.transport.send(this.last_response)) {
      this.onTransportError();
    }
  }

  // INVITE Server Transaction RFC 3261 17.2.1.
  void receiveResponse(int status_code, IncomingMessage response,
      [void Function() onSuccess, void Function() onFailure]) {
    if (status_code >= 100 && status_code <= 199) {
      switch (this.state) {
        case TransactionState.PROCEEDING:
          if (!this.transport.send(response)) {
            this.onTransportError();
          }
          this.last_response = response;
          break;
        default:
          break;
      }
    }

    if (status_code > 100 &&
        status_code <= 199 &&
        this.state == TransactionState.PROCEEDING) {
      // Trigger the resendProvisionalTimer only for the first non 100 provisional response.
      if (this.resendProvisionalTimer == null) {
        this.resendProvisionalTimer = setInterval(() {
          this.resend_provisional();
        }, Timers.PROVISIONAL_RESPONSE_INTERVAL);
      }
    } else if (status_code >= 200 && status_code <= 299) {
      if (this.state == TransactionState.PROCEEDING) {
        this.stateChanged(TransactionState.ACCEPTED);
        this.last_response = response;
        this.L = setTimeout(() {
          this.timer_L();
        }, Timers.TIMER_L);

        if (this.resendProvisionalTimer != null) {
          clearInterval(this.resendProvisionalTimer);
          this.resendProvisionalTimer = null;
        }
      }
      /* falls through */
      if (this.state == TransactionState.ACCEPTED) {
        // Note that this point will be reached for proceeding this.state also.
        if (!this.transport.send(response)) {
          this.onTransportError();
          if (onFailure != null) {
            onFailure();
          }
        } else if (onSuccess != null) {
          onSuccess();
        }
      }
    } else if (status_code >= 300 && status_code <= 699) {
      switch (this.state) {
        case TransactionState.PROCEEDING:
          if (this.resendProvisionalTimer != null) {
            clearInterval(this.resendProvisionalTimer);
            this.resendProvisionalTimer = null;
          }

          if (!this.transport.send(response)) {
            this.onTransportError();
            if (onFailure != null) {
              onFailure();
            }
          } else {
            this.stateChanged(TransactionState.COMPLETED);
            this.H = setTimeout(() {
              this.timer_H();
            }, Timers.TIMER_H);
            if (onSuccess != null) {
              onSuccess();
            }
          }
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
