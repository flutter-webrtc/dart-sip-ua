import 'package:events2/events2.dart';
import '../sip_ua.dart';
import 'Constants.dart' as DartSIP_C;
import 'Constants.dart';
import 'SIPMessage.dart' as SIPMessage;
import 'Timers.dart';
import 'Transport.dart';
import 'Utils.dart';
import 'logger.dart';

final nict_logger = new Logger('NonInviteClientTransaction');
debugnict(msg) => nict_logger.debug(msg);
final ict_logger = new Logger('InviteClientTransaction');
debugict(msg) => ict_logger.debug(msg);
final act_logger = new Logger('AckClientTransaction');
debugact(msg) => act_logger.debug(msg);
final nist_logger = new Logger('NonInviteServerTransaction');
debugnist(msg) => nist_logger.debug(msg);
final ist_logger = new Logger('InviteServerTransaction');
debugist(msg) => ist_logger.debug(msg);

class C {
  // Transaction states.
  static const STATUS_TRYING = 1;
  static const STATUS_PROCEEDING = 2;
  static const STATUS_CALLING = 3;
  static const STATUS_ACCEPTED = 4;
  static const STATUS_COMPLETED = 5;
  static const STATUS_TERMINATED = 6;
  static const STATUS_CONFIRMED = 7;

  // Transaction types.
  static const NON_INVITE_CLIENT = 'nict';
  static const NON_INVITE_SERVER = 'nist';
  static const INVITE_CLIENT = 'ict';
  static const INVITE_SERVER = 'ist';
}

class NonInviteClientTransaction extends EventEmitter {
  var type;
  var id;
  UA ua;
  Transport transport;
  var request;
  var eventHandlers;
  var F, K;
  var state;

  NonInviteClientTransaction(UA ua, Transport transport, request, eventHandlers) {
    this.type = C.NON_INVITE_CLIENT;
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
    this.stateChanged(C.STATUS_TRYING);
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
    this.stateChanged(C.STATUS_TERMINATED);
    this.ua.destroyTransaction(this);
    this.eventHandlers['onTransportError']();
  }

  timer_F() {
    debugnict('Timer F expired for transaction ${this.id}');
    this.stateChanged(C.STATUS_TERMINATED);
    this.ua.destroyTransaction(this);
    this.eventHandlers['onRequestTimeout']();
  }

  timer_K() {
    this.stateChanged(C.STATUS_TERMINATED);
    this.ua.destroyTransaction(this);
  }

  receiveResponse(SIPMessage.IncomingResponse response) {
    var status_code = response.status_code;

    if (status_code < 200) {
      switch (this.state) {
        case C.STATUS_TRYING:
        case C.STATUS_PROCEEDING:
          this.stateChanged(C.STATUS_PROCEEDING);
          this.eventHandlers['onReceiveResponse'](response);
          break;
      }
    } else {
      switch (this.state) {
        case C.STATUS_TRYING:
        case C.STATUS_PROCEEDING:
          this.stateChanged(C.STATUS_COMPLETED);
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
        case C.STATUS_COMPLETED:
          break;
      }
    }
  }
}

class InviteClientTransaction extends EventEmitter {
  var type;
  var id;
  UA ua;
  Transport transport;
  var request;
  var eventHandlers;
  var state;
  var B, D, M;

  InviteClientTransaction(UA ua, Transport transport, request, eventHandlers) {
    this.type = C.INVITE_CLIENT;
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

  stateChanged(state) {
    this.state = state;
    this.emit('stateChanged');
  }

  send() {
    this.stateChanged(C.STATUS_CALLING);
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

    if (this.state != C.STATUS_ACCEPTED) {
      debugict('transport error occurred, deleting transaction ${this.id}');
      this.eventHandlers['onTransportError']();
    }

    this.stateChanged(C.STATUS_TERMINATED);
    this.ua.destroyTransaction(this);
  }

  // RFC 6026 7.2.
  timer_M() {
    debugict('Timer M expired for transaction ${this.id}');

    if (this.state == C.STATUS_ACCEPTED) {
      clearTimeout(this.B);
      this.stateChanged(C.STATUS_TERMINATED);
      this.ua.destroyTransaction(this);
    }
  }

  // RFC 3261 17.1.1.
  timer_B() {
    debugict('Timer B expired for transaction ${this.id}');
    if (this.state == C.STATUS_CALLING) {
      this.stateChanged(C.STATUS_TERMINATED);
      this.ua.destroyTransaction(this);
      this.eventHandlers['onRequestTimeout']();
    }
  }

  timer_D() {
    debugict('Timer D expired for transaction ${this.id}');
    clearTimeout(this.B);
    this.stateChanged(C.STATUS_TERMINATED);
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
    if (this.state != C.STATUS_PROCEEDING) {
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

  receiveResponse(SIPMessage.IncomingResponse response) {
    var status_code = response.status_code;

    if (status_code >= 100 && status_code <= 199) {
      switch (this.state) {
        case C.STATUS_CALLING:
          this.stateChanged(C.STATUS_PROCEEDING);
          this.eventHandlers['onReceiveResponse'](response);
          break;
        case C.STATUS_PROCEEDING:
          this.eventHandlers['onReceiveResponse'](response);
          break;
      }
    } else if (status_code >= 200 && status_code <= 299) {
      switch (this.state) {
        case C.STATUS_CALLING:
        case C.STATUS_PROCEEDING:
          this.stateChanged(C.STATUS_ACCEPTED);
          this.M = setTimeout(() {
            this.timer_M();
          }, Timers.TIMER_M);
          this.eventHandlers['onReceiveResponse'](response);
          break;
        case C.STATUS_ACCEPTED:
          this.eventHandlers['onReceiveResponse'](response);
          break;
      }
    } else if (status_code >= 300 && status_code <= 699) {
      switch (this.state) {
        case C.STATUS_CALLING:
        case C.STATUS_PROCEEDING:
          this.stateChanged(C.STATUS_COMPLETED);
          this.sendACK(response);
          this.eventHandlers['onReceiveResponse'](response);
          break;
        case C.STATUS_COMPLETED:
          this.sendACK(response);
          break;
      }
    }
  }
}

class AckClientTransaction extends EventEmitter {
  var id;
  Transport transport;
  var request;
  var eventHandlers;

  AckClientTransaction(UA ua, Transport transport, request, eventHandlers) {
    this.id = 'z9hG4bK${Math.floor(Math.random() * 10000000)}';
    this.transport = transport;
    this.request = request;
    this.eventHandlers = eventHandlers;

    var via = 'SIP/2.0/${transport.via_transport}';

    via += ' ${ua.configuration.via_host};branch=${this.id}';

    this.request.setHeader('via', via);
  }

  send() {
    if (!this.transport.send(this.request)) {
      this.onTransportError();
    }
  }

  onTransportError() {
    debugact('transport error occurred for transaction ${this.id}');
    this.eventHandlers['onTransportError']();
  }
}

class NonInviteServerTransaction extends EventEmitter {
  var type;
  var id;
  UA ua;
  Transport transport;
  var request;
  var last_response;
  var state;
  var transportError;
  var J;

  NonInviteServerTransaction(UA ua, Transport transport, request) {
    this.type = C.NON_INVITE_SERVER;
    this.id = request.via_branch;
    this.ua = ua;
    this.transport = transport;
    this.request = request;
    this.last_response = '';
    request.server_transaction = this;

    this.state = C.STATUS_TRYING;

    ua.newTransaction(this);
  }

  stateChanged(state) {
    this.state = state;
    this.emit('stateChanged');
  }

  timer_J() {
    debugnist('Timer J expired for transaction ${this.id}');
    this.stateChanged(C.STATUS_TERMINATED);
    this.ua.destroyTransaction(this);
  }

  onTransportError() {
    if (this.transportError == null) {
      this.transportError = true;

      debugnist('transport error occurred, deleting transaction ${this.id}');

      clearTimeout(this.J);
      this.stateChanged(C.STATUS_TERMINATED);
      this.ua.destroyTransaction(this);
    }
  }

  receiveResponse(status_code, response, onSuccess, onFailure) {
    if (status_code == 100) {
      /* RFC 4320 4.1
       * 'A SIP element MUST NOT
       * send any provisional response with a
       * Status-Code other than 100 to a non-INVITE request.'
       */
      switch (this.state) {
        case C.STATUS_TRYING:
          this.stateChanged(C.STATUS_PROCEEDING);
          if (!this.transport.send(response)) {
            this.onTransportError();
          }
          break;
        case C.STATUS_PROCEEDING:
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
      }
    } else if (status_code >= 200 && status_code <= 699) {
      switch (this.state) {
        case C.STATUS_TRYING:
        case C.STATUS_PROCEEDING:
          this.stateChanged(C.STATUS_COMPLETED);
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
        case C.STATUS_COMPLETED:
          break;
      }
    }
  }
}

class InviteServerTransaction extends EventEmitter {
  var type;
  var id;
  UA ua;
  Transport transport;
  var request;
  var last_response;
  var state;
  var resendProvisionalTimer;
  var transportError;
  var L, H, I;

  InviteServerTransaction(UA ua, Transport transport, request) {
    this.type = C.INVITE_SERVER;
    this.id = request.via_branch;
    this.ua = ua;
    this.transport = transport;
    this.request = request;
    this.last_response = '';
    request.server_transaction = this;

    this.state = C.STATUS_PROCEEDING;

    ua.newTransaction(this);

    this.resendProvisionalTimer = null;

    request.reply(100);
  }

  stateChanged(state) {
    this.state = state;
    this.emit('stateChanged');
  }

  timer_H() {
    debugist('Timer H expired for transaction ${this.id}');

    if (this.state == C.STATUS_COMPLETED) {
      debugist('ACK not received, dialog will be terminated');
    }

    this.stateChanged(C.STATUS_TERMINATED);
    this.ua.destroyTransaction(this);
  }

  timer_I() {
    this.stateChanged(C.STATUS_TERMINATED);
  }

  // RFC 6026 7.1.
  timer_L() {
    debugist('Timer L expired for transaction ${this.id}');

    if (this.state == C.STATUS_ACCEPTED) {
      this.stateChanged(C.STATUS_TERMINATED);
      this.ua.destroyTransaction(this);
    }
  }

  onTransportError() {
    if (this.transportError == null) {
      this.transportError = true;

      debugist('transport error occurred, deleting transaction ${this.id}');

      if (this.resendProvisionalTimer != null) {
        clearInterval(this.resendProvisionalTimer);
        this.resendProvisionalTimer = null;
      }

      clearTimeout(this.L);
      clearTimeout(this.H);
      clearTimeout(this.I);

      this.stateChanged(C.STATUS_TERMINATED);
      this.ua.destroyTransaction(this);
    }
  }

  resend_provisional() {
    if (!this.transport.send(this.last_response)) {
      this.onTransportError();
    }
  }

  // INVITE Server Transaction RFC 3261 17.2.1.
  receiveResponse(status_code, response, onSuccess, onFailure) {
    if (status_code >= 100 && status_code <= 199) {
      switch (this.state) {
        case C.STATUS_PROCEEDING:
          if (!this.transport.send(response)) {
            this.onTransportError();
          }
          this.last_response = response;
          break;
      }
    }

    if (status_code > 100 &&
        status_code <= 199 &&
        this.state == C.STATUS_PROCEEDING) {
      // Trigger the resendProvisionalTimer only for the first non 100 provisional response.
      if (this.resendProvisionalTimer == null) {
        this.resendProvisionalTimer = setInterval(() {
          this.resend_provisional();
        }, Timers.PROVISIONAL_RESPONSE_INTERVAL);
      }
    } else if (status_code >= 200 && status_code <= 299) {
      if (this.state == C.STATUS_PROCEEDING) {
        this.stateChanged(C.STATUS_ACCEPTED);
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
      if (this.state == C.STATUS_ACCEPTED) {
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
        case C.STATUS_PROCEEDING:
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
            this.stateChanged(C.STATUS_COMPLETED);
            this.H = setTimeout(() {
              this.timer_H();
            }, Timers.TIMER_H);
            if (onSuccess != null) {
              onSuccess();
            }
          }
          break;
      }
    }
  }
}

/**
 * INVITE:
 *  _true_ if retransmission
 *  _false_ new request
 *
 * ACK:
 *  _true_  ACK to non2xx response
 *  _false_ ACK must be passed to TU (accepted state)
 *          ACK to 2xx response
 *
 * CANCEL:
 *  _true_  no matching invite transaction
 *  _false_ matching invite transaction and no final response sent
 *
 * OTHER:
 *  _true_  retransmission
 *  _false_ new request
 */
checkTransaction(_transactions, request) {
  var tr;
  switch (request.method) {
    case SipMethod.INVITE:
      tr = _transactions['ist'][request.via_branch];
      if (tr != null) {
        switch (tr.state) {
          case C.STATUS_PROCEEDING:
            tr.transport.send(tr.last_response);
            break;

          // RFC 6026 7.1 Invite retransmission.
          // Received while in C.STATUS_ACCEPTED state. Absorb it.
          case C.STATUS_ACCEPTED:
            break;
        }

        return true;
      }
      break;
    case SipMethod.ACK:
      tr = _transactions['ist'][request.via_branch];

      // RFC 6026 7.1.
      if (tr != null) {
        if (tr.state == C.STATUS_ACCEPTED) {
          return false;
        } else if (tr.state == C.STATUS_COMPLETED) {
          tr.state = C.STATUS_CONFIRMED;
          tr.I = setTimeout(() {
            tr.timer_I();
          }, Timers.TIMER_I);

          return true;
        }
      }
      // ACK to 2XX Response.
      else {
        return false;
      }
      break;
    case SipMethod.CANCEL:
      tr = _transactions['ist'][request.via_branch];
      if (tr != null) {
        request.reply_sl(200);
        if (tr.state == C.STATUS_PROCEEDING) {
          return false;
        } else {
          return true;
        }
      } else {
        request.reply_sl(481);
        return true;
      }
      break;
    default:
      // Non-INVITE Server Transaction RFC 3261 17.2.2.
      tr = _transactions['nist'][request.via_branch];
      if (tr != null) {
        switch (tr.state) {
          case C.STATUS_TRYING:
            break;
          case C.STATUS_PROCEEDING:
          case C.STATUS_COMPLETED:
            tr.transport.send(tr.last_response);
            break;
        }

        return true;
      }
      break;
  }
  return false;
}
