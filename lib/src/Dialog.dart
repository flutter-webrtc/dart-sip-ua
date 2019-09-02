import 'SIPMessage.dart' as SIPMessage;
import 'Constants.dart' as DartSIP_C;
import 'Transactions.dart' as Transactions;
import 'Exceptions.dart' as Exceptions;
import 'Dialog/RequestSender.dart';
import 'Utils.dart' as Utils;
import 'logger.dart';

class Dialog_C {
  // Dialog states.
  static const STATUS_EARLY = 1;
  static const STATUS_CONFIRMED = 2;
}

class Id {
  var call_id;
  var local_tag;
  var remote_tag;

  factory Id.fromMap(map) {
    return new Id(map['call_id'], map['local_tag'], map['remote_tag']);
  }

  Id(this.call_id, this.local_tag, this.remote_tag);

  toString() {
    return this.call_id + this.local_tag + this.remote_tag;
  }
}

// RFC 3261 12.1.
class Dialog {
  var _owner;
  var _ua;
  var _uac_pending_reply;
  var _uas_pending_reply;
  var _state;
  var _remote_seqnum;
  var _local_uri;
  var _remote_uri;
  var _remote_target;
  var _route_set;
  var _ack_seqnum;
  var _id;
  var _local_seqnum;
  final logger = new Logger('Dialog');
  debug(msg) => logger.debug(msg);
  debugerror(error) => logger.error(error);

  Dialog(owner, message, type, [state]) {
    state = state ?? Dialog_C.STATUS_CONFIRMED;
    this._owner = owner;
    this._ua = owner._ua;

    this._uac_pending_reply = false;
    this._uas_pending_reply = false;

    if (!message.hasHeader('contact')) {
      throw new Exceptions.TypeError(
          'unable to create a Dialog without Contact header field');
    }

    if (message is SIPMessage.IncomingResponse) {
      state = (message.status_code < 200) ? Dialog_C.STATUS_EARLY : Dialog_C.STATUS_CONFIRMED;
    }

    var contact = message.parseHeader('contact');

    // RFC 3261 12.1.1.
    if (type == 'UAS') {
      this._id = Id.fromMap({
        'call_id': message.call_id,
        'local_tag': message.from_tag,
        'remote_tag': message.to_tag,
      });

      this._state = state;
      this._remote_seqnum = message.cseq;
      this._local_uri = message.parseHeader('to').uri;
      this._remote_uri = message.parseHeader('from').uri;
      this._remote_target = contact.uri;
      this._route_set = message.getHeaders('record-route');
      this._ack_seqnum = this._remote_seqnum;
    }
    // RFC 3261 12.1.2.
    else if (type == 'UAC') {
      this._id = Id.fromMap({
        'call_id': message.call_id,
        'local_tag': message.from_tag,
        'remote_tag': message.to_tag,
      });
      this._state = state;
      this._local_seqnum = message.cseq;
      this._local_uri = message.parseHeader('from').uri;
      this._remote_uri = message.parseHeader('to').uri;
      this._remote_target = contact.uri;
      this._route_set = message.getHeaders('record-route').reverse();
      this._ack_seqnum = null;
    }

    this._ua.newDialog(this);
    debug(
        'new ${type} dialog created with status ${this._state == Dialog_C.STATUS_EARLY ? 'EARLY' : 'CONFIRMED'}');
  }

  get id => this._id;

  get local_seqnum => this._local_seqnum;

  set local_seqnum(num) {
    this._local_seqnum = num;
  }

  get owner => this._owner;

  get uac_pending_reply => this._uac_pending_reply;

  set uac_pending_reply(pending) {
    this._uac_pending_reply = pending;
  }

  get uas_pending_reply => this._uas_pending_reply;

  update(message, type) {
    this._state = Dialog_C.STATUS_CONFIRMED;

    debug('dialog ${this._id.toString()}  changed to CONFIRMED state');

    if (type == 'UAC') {
      // RFC 3261 13.2.2.4.
      this._route_set = message.getHeaders('record-route').reverse();
    }
  }

  terminate() {
    debug('dialog ${this._id.toString()} deleted');
    this._ua.destroyDialog(this);
  }

  sendRequest(method, options) {
    options = options ?? {};
    var extraHeaders = Utils.cloneArray(options['extraHeaders']);
    var eventHandlers = options['eventHandlers'] ?? {};
    var body = options['body'] ?? null;
    var request = this._createRequest(method, extraHeaders, body);

    // Increase the local CSeq on authentication.
    eventHandlers['onAuthenticated'] = (request) {
      this._local_seqnum += 1;
    };

    var request_sender = new DialogRequestSender(this, request, eventHandlers);

    request_sender.send();

    // Return the instance of OutgoingRequest.
    return request;
  }

  receiveRequest(request) {
    // Check in-dialog request.
    if (!this._checkInDialogRequest(request)) {
      return;
    }

    // ACK received. Cleanup this._ack_seqnum.
    if (request.method == DartSIP_C.ACK && this._ack_seqnum != null) {
      this._ack_seqnum = null;
    }
    // INVITE received. Set this._ack_seqnum.
    else if (request.method == DartSIP_C.INVITE) {
      this._ack_seqnum = request.cseq;
    }

    this._owner.receiveRequest(request);
  }

  // RFC 3261 12.2.1.1.
  _createRequest(method, extraHeaders, body) {
    extraHeaders = Utils.cloneArray(extraHeaders);

    if (this._local_seqnum == null) {
      this._local_seqnum = Utils.Math.floor(Utils.Math.random() * 10000);
    }

    var cseq = (method == DartSIP_C.CANCEL || method == DartSIP_C.ACK)
        ? 'this._local_seqnum'
        : this._local_seqnum += 1;

    var request = new SIPMessage.OutgoingRequest(
        method,
        this._remote_target,
        this._ua,
        {
          'cseq': cseq,
          'call_id': this._id.call_id,
          'from_uri': this._local_uri,
          'from_tag': this._id.local_tag,
          'to_uri': this._remote_uri,
          'to_tag': this._id.remote_tag,
          'route_set': this._route_set
        },
        extraHeaders,
        body);

    return request;
  }

  // RFC 3261 12.2.2.
  _checkInDialogRequest(request) {
    if (this._remote_seqnum == null) {
      this._remote_seqnum = request.cseq;
    } else if (request.cseq < this._remote_seqnum) {
      if (request.method == DartSIP_C.ACK) {
        // We are not expecting any ACK with lower seqnum than the current one.
        // Or this is not the ACK we are waiting for.
        if (this._ack_seqnum == null || request.cseq != this._ack_seqnum) {
          return false;
        }
      } else {
        request.reply(500);

        return false;
      }
    } else if (request.cseq > this._remote_seqnum) {
      this._remote_seqnum = request.cseq;
    }

    // RFC3261 14.2 Modifying an Existing Session -UAS BEHAVIOR-.
    if (request.method == DartSIP_C.INVITE ||
        (request.method == DartSIP_C.UPDATE && request.body)) {
      if (this._uac_pending_reply == true) {
        request.reply(491);
      } else if (this._uas_pending_reply == true) {
        var retryAfter = (Utils.Math.randomDouble() * 10 | 0) + 1;
        request.reply(500, null, ['Retry-After:${retryAfter}']);
        return false;
      } else {
        this._uas_pending_reply = true;
        var stateChanged;
        stateChanged = () {
          if (request.server_transaction.state ==
                  Transactions.C.STATUS_ACCEPTED ||
              request.server_transaction.state ==
                  Transactions.C.STATUS_COMPLETED ||
              request.server_transaction.state ==
                  Transactions.C.STATUS_TERMINATED) {
            request.server_transaction.remove('stateChanged', stateChanged);
            this._uas_pending_reply = false;
          }
        };
        request.server_transaction.on('stateChanged', stateChanged);
      }

      // RFC3261 12.2.2 Replace the dialog's remote target URI if the request is accepted.
      if (request.hasHeader('contact')) {
        request.server_transaction.on('stateChanged', () {
          if (request.server_transaction.state ==
              Transactions.C.STATUS_ACCEPTED) {
            this._remote_target = request.parseHeader('contact').uri;
          }
        });
      }
    } else if (request.method == DartSIP_C.NOTIFY) {
      // RFC6665 3.2 Replace the dialog's remote target URI if the request is accepted.
      if (request.hasHeader('contact')) {
        request.server_transaction.on('stateChanged', () {
          if (request.server_transaction.state ==
              Transactions.C.STATUS_COMPLETED) {
            this._remote_target = request.parseHeader('contact').uri;
          }
        });
      }
    }
    return true;
  }
}
