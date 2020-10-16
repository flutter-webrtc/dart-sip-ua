import 'package:sip_ua/src/rtc_session.dart';

import '../../sip_ua.dart';
import '../constants.dart' as DartSIP_C;
import '../constants.dart';
import '../grammar.dart';
import '../utils.dart' as Utils;
import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../logger.dart';
import '../rtc_session.dart' as rtc;

class ReferSubscriber extends EventManager {
  String _id;
  final rtc.RTCSession _session;

  ReferSubscriber(this._session);

  String get id => _id;

  void sendRefer(target, options) {
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
        'Referred-By: <${_session.ua.configuration.uri.scheme}:${_session.ua.configuration.uri.user}@${_session.ua.configuration.uri.host}>';

    extraHeaders.add(referredBy);
    extraHeaders.add('Contact: ${_session.contact}');

    EventManager handlers = EventManager();
    handlers.on(EventOnSuccessResponse(), (EventOnSuccessResponse event) {
      _requestSucceeded(event.response);
    });
    handlers.on(EventOnErrorResponse(), (EventOnErrorResponse event) {
      _requestFailed(event.response, DartSIP_C.causes.REJECTED);
    });
    handlers.on(EventOnTransportError(), (EventOnTransportError event) {
      _requestFailed(null, DartSIP_C.causes.CONNECTION_ERROR);
    });
    handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout event) {
      _requestFailed(null, DartSIP_C.causes.REQUEST_TIMEOUT);
    });
    handlers.on(EventOnDialogError(), (EventOnDialogError event) {
      _requestFailed(null, DartSIP_C.causes.DIALOG_ERROR);
    });

    var request = _session.sendRequest(SipMethod.REFER,
        {'extraHeaders': extraHeaders, 'eventHandlers': handlers});

    _id = request.cseq;
  }

  void receiveNotify(request) {
    logger.debug('receiveNotify()');

    if (request.body == null) {
      return;
    }

    var status_line = request.body.trim();
    var parsed = Grammar.parse(status_line, 'Status_Line');

    if (parsed == -1) {
      logger.debug(
          'receiveNotify() | error parsing NOTIFY body: "${request.body}"');
      return;
    }

    var status_code = parsed.status_code.toString();
    if (Utils.test100(status_code)) {
      /// 100 Trying
      emit(EventReferTrying(request: request, status_line: status_line));
    } else if (Utils.test1XX(status_code)) {
      /// 1XX Progressing
      emit(EventReferProgress(request: request, status_line: status_line));
    } else if (Utils.test2XX(status_code)) {
      /// 2XX OK
      emit(EventReferAccepted(request: request, status_line: status_line));
    } else {
      /// 200+ Error
      emit(EventReferFailed(request: request, status_line: status_line));
    }
  }

  void _requestSucceeded(response) {
    logger.debug('REFER succeeded');

    logger.debug('emit "requestSucceeded"');

    emit(EventReferRequestSucceeded(response: response));
  }

  void _requestFailed(response, cause) {
    logger.debug('REFER failed');

    logger.debug('emit "requestFailed"');

    emit(EventReferRequestFailed(response: response, cause: cause));
  }
}
