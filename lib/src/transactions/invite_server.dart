import 'dart:async';

import '../event_manager/internal_events.dart';
import '../logger.dart';
import '../sip_message.dart';
import '../socket_transport.dart';
import '../timers.dart';
import '../ua.dart';
import 'transaction_base.dart';

class InviteServerTransaction extends TransactionBase {
  InviteServerTransaction(
      UA ua, SocketTransport? transport, IncomingRequest request) {
    id = request.via_branch;
    this.ua = ua;
    this.transport = transport;
    this.request = request;
    last_response = IncomingMessage();
    request.server_transaction = this;

    state = TransactionState.PROCEEDING;

    ua.newTransaction(this);

    _resendProvisionalTimer = null;

    request.reply(100);
  }
  Timer? _resendProvisionalTimer;
  bool? transportError;
  Timer? L, H, I;

  void stateChanged(TransactionState state) {
    this.state = state;
    emit(EventStateChanged());
  }

  void timer_H() {
    logger.d('Timer H expired for transaction $id');

    if (state == TransactionState.COMPLETED) {
      logger.d('ACK not received, dialog will be terminated');
    }

    stateChanged(TransactionState.TERMINATED);
    ua.destroyTransaction(this);
  }

  void timer_I() {
    stateChanged(TransactionState.TERMINATED);
  }

  // RFC 6026 7.1.
  void timer_L() {
    logger.d('Timer L expired for transaction $id');

    if (state == TransactionState.ACCEPTED) {
      stateChanged(TransactionState.TERMINATED);
      ua.destroyTransaction(this);
    }
  }

  @override
  void onTransportError() {
    if (transportError == null) {
      transportError = true;

      logger.d('transport error occurred, deleting transaction $id');

      if (_resendProvisionalTimer != null) {
        clearInterval(_resendProvisionalTimer);
        _resendProvisionalTimer = null;
      }

      clearTimeout(L);
      clearTimeout(H);
      clearTimeout(I);

      stateChanged(TransactionState.TERMINATED);
      ua.destroyTransaction(this);
    }
  }

  void resend_provisional() {
    if (!transport!.send(last_response)) {
      onTransportError();
    }
  }

  // INVITE Server Transaction RFC 3261 17.2.1.
  @override
  void receiveResponse(int status_code, IncomingMessage response,
      [void Function()? onSuccess, void Function()? onFailure]) {
    if (status_code >= 100 && status_code <= 199) {
      switch (state) {
        case TransactionState.PROCEEDING:
          if (!transport!.send(response)) {
            onTransportError();
          }
          last_response = response;
          break;
        default:
          break;
      }
    }

    if (status_code > 100 &&
        status_code <= 199 &&
        state == TransactionState.PROCEEDING) {
      // Trigger the resendProvisionalTimer only for the first non 100 provisional response.
      _resendProvisionalTimer ??= setInterval(() {
        resend_provisional();
      }, Timers.PROVISIONAL_RESPONSE_INTERVAL);
    } else if (status_code >= 200 && status_code <= 299) {
      if (state == TransactionState.PROCEEDING) {
        stateChanged(TransactionState.ACCEPTED);
        last_response = response;
        L = setTimeout(() {
          timer_L();
        }, Timers.TIMER_L);

        if (_resendProvisionalTimer != null) {
          clearInterval(_resendProvisionalTimer);
          _resendProvisionalTimer = null;
        }
      }
      /* falls through */
      if (state == TransactionState.ACCEPTED) {
        // Note that this point will be reached for proceeding state also.
        if (!transport!.send(response)) {
          onTransportError();
          if (onFailure != null) {
            onFailure();
          }
        } else if (onSuccess != null) {
          onSuccess();
        }
      }
    } else if (status_code >= 300 && status_code <= 699) {
      switch (state) {
        case TransactionState.PROCEEDING:
          if (_resendProvisionalTimer != null) {
            clearInterval(_resendProvisionalTimer);
            _resendProvisionalTimer = null;
          }

          if (!transport!.send(response)) {
            onTransportError();
            if (onFailure != null) {
              onFailure();
            }
          } else {
            stateChanged(TransactionState.COMPLETED);
            H = setTimeout(() {
              timer_H();
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
    throw Exception('Not Implemented');
  }
}
