import '../../sip_ua.dart';
import '../Constants.dart' as DartSIP_C;
import '../Constants.dart';
import '../Grammar.dart';
import '../Utils.dart' as Utils;
import '../event_manager/event_manager.dart';
import '../logger.dart';

class ReferSubscriber extends EventManager {
  var _id = null;
  var _session = null;
  final logger = Log();

  ReferSubscriber(this._session);

  get id => this._id;

  sendRefer(target, options) {
    logger.debug('sendRefer()');

    var extraHeaders = Utils.cloneArray(options['extraHeaders']);
    EventManager eventHandlers = options['eventHandlers'] ?? EventManager();

    // Set event handlers.
    addAllEventHandlers(eventHandlers);

    // Replaces URI header field.
    String replaces;

    if (options['replaces'] != null) {
      replaces = options['replaces']._request.call_id;
      replaces += ';to-tag=${options['replaces']._to_tag}';
      replaces += ';from-tag=${options['replaces']._from_tag}';
      replaces = Utils.encodeURIComponent(replaces);
    }

    // Refer-To header field.
    var referTo = 'Refer-To: <$target' +
        (replaces != null ? '?Replaces=$replaces' : '') +
        '>';

    extraHeaders.add(referTo);

    // Referred-By header field.
    var referredBy =
        'Referred-By: <${this._session._ua._configuration.uri._scheme}:${this._session._ua._configuration.uri._user}@${this._session._ua._configuration.uri._host}>';

    extraHeaders.add(referredBy);

    extraHeaders.add('Contact: ${this._session.contact}');

    EventManager handlers = EventManager();
    handlers.on(EventOnSuccessResponse(), (EventOnSuccessResponse event) {
      this._requestSucceeded(event.response);
    });
    handlers.on(EventOnErrorResponse(), (EventOnErrorResponse event) {
      this._requestFailed(event.response, DartSIP_C.causes.REJECTED);
    });

    handlers.on(EventOnTransportError(), (EventOnTransportError event) {
      this._requestFailed(null, DartSIP_C.causes.CONNECTION_ERROR);
    });

    handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout event) {
      this._requestFailed(null, DartSIP_C.causes.REQUEST_TIMEOUT);
    });
    handlers.on(EventOnDialogError(), (EventOnDialogError event) {
      this._requestFailed(null, DartSIP_C.causes.DIALOG_ERROR);
    });

    var request = this._session.sendRequest(SipMethod.REFER,
        {'extraHeaders': extraHeaders, 'eventHandlers': handlers});

    this._id = request.cseq;
  }

  receiveNotify(request) {
    logger.debug('receiveNotify()');

    if (request.body == null) {
      return;
    }

    var status_line = Grammar.parse(request.body.trim(), 'Status_Line');

    if (status_line == -1) {
      logger.debug(
          'receiveNotify() | error parsing NOTIFY body: "${request.body}"');
      return;
    }

    var status_code = status_line.status_code.toString();
    if (Utils.test100(status_code)) {
      /// 100 Trying
      this.emit(EventTrying(request: request, status_line: status_line));
    } else if (Utils.test1XX(status_code)) {
      /// 1XX Progressing
      this.emit(EventProgress(request: request, status_line: status_line));
    } else if (Utils.test2XX(status_code)) {
      /// 2XX OK
      this.emit(EventAccepted(request: request, status_line: status_line));
    } else {
      /// 200+ Error
      this.emit(EventFailed(request: request, status_line: status_line));
    }
  }

  _requestSucceeded(response) {
    logger.debug('REFER succeeded');

    logger.debug('emit "requestSucceeded"');

    this.emit(EventRequestSucceeded(response: response));
  }

  _requestFailed(response, cause) {
    logger.debug('REFER failed');

    logger.debug('emit "requestFailed"');

    this.emit(EventRequestFailed(response: response, cause: cause));
  }
}
