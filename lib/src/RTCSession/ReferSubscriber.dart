import 'package:events2/events2.dart';

import '../Constants.dart' as DartSIP_C;
import '../Constants.dart';
import '../Grammar.dart';
import '../Utils.dart' as Utils;
import '../logger.dart';

class ReferSubscriber extends EventEmitter {
  var _id = null;
  var _session = null;
  final logger = Logger('RTCSession:ReferSubscriber');
  debug(msg) => logger.debug(msg);
  debugerror(error) => logger.error(error);

  ReferSubscriber(this._session);

  get id => this._id;

  sendRefer(target, options) {
    debug('sendRefer()');

    var extraHeaders = Utils.cloneArray(options['extraHeaders']);
    var eventHandlers = options['eventHandlers'] ?? {};

    // Set event handlers.
    for (var event in eventHandlers) {
      if (eventHandlers.containsKey(event)) {
        this.on(event, eventHandlers[event]);
      }
    }

    // Replaces URI header field.
    String replaces;

    if (options['replaces'] != null) {
      replaces = options['replaces']._request.call_id;
      replaces += ';to-tag=${options['replaces']._to_tag}';
      replaces += ';from-tag=${options['replaces']._from_tag}';
      replaces = Utils.encodeURIComponent(replaces);
    }

    // Refer-To header field.
    var referTo =
        'Refer-To: <$target' + (replaces != null ? '?Replaces=$replaces' : '') + '>';

    extraHeaders.add(referTo);

    // Referred-By header field.
    var referredBy =
        'Referred-By: <${this._session._ua._configuration.uri._scheme}:${this._session._ua._configuration.uri._user}@${this._session._ua._configuration.uri._host}>';

    extraHeaders.add(referredBy);

    extraHeaders.add('Contact: ${this._session.contact}');

    var request = this._session.sendRequest(SipMethod.REFER, {
      'extraHeaders': extraHeaders,
      'eventHandlers': {
        'onSuccessResponse': (response) {
          this._requestSucceeded(response);
        },
        'onErrorResponse': (response) {
          this._requestFailed(response, DartSIP_C.causes.REJECTED);
        },
        'onTransportError': () {
          this._requestFailed(null, DartSIP_C.causes.CONNECTION_ERROR);
        },
        'onRequestTimeout': () {
          this._requestFailed(null, DartSIP_C.causes.REQUEST_TIMEOUT);
        },
        'onDialogError': () {
          this._requestFailed(null, DartSIP_C.causes.DIALOG_ERROR);
        }
      }
    });

    this._id = request.cseq;
  }

  receiveNotify(request) {
    debug('receiveNotify()');

    if (request.body == null) {
      return;
    }

    var status_line = Grammar.parse(request.body.trim(), 'Status_Line');

    if (status_line == -1) {
      debug('receiveNotify() | error parsing NOTIFY body: "${request.body}"');
      return;
    }

    var status_code = status_line.status_code.toString();
    if (Utils.test100(status_code)) {
      /// 100 Trying
      this.emit('trying', {'request': request, 'status_line': status_line});
    } else if (Utils.test1XX(status_code)) {
      /// 1XX Progressing
      this.emit('progress', {'request': request, 'status_line': status_line});
    } else if (Utils.test2XX(status_code)) {
      /// 2XX OK
      this.emit('accepted', {'request': request, 'status_line': status_line});
    } else {
      /// 200+ Error
      this.emit('failed', {'request': request, 'status_line': status_line});
    }
  }

  _requestSucceeded(response) {
    debug('REFER succeeded');

    debug('emit "requestSucceeded"');

    this.emit('requestSucceeded', {'response': response});
  }

  _requestFailed(response, cause) {
    debug('REFER failed');

    debug('emit "requestFailed"');

    this.emit('requestFailed', {'response': response ?? null, 'cause': cause});
  }
}
