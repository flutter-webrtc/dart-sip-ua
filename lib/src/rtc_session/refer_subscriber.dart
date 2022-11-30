import 'package:sip_ua/src/sip_message.dart';
import '../constants.dart' as DartSIP_C;
import '../constants.dart';
import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../grammar.dart';
import '../logger.dart';
import '../rtc_session.dart' as rtc;
import '../uri.dart';
import '../utils.dart' as Utils;

class ReferSubscriber extends EventManager {
  ReferSubscriber(this._session);

  int? _id;
  final rtc.RTCSession _session;

  int? get id => _id;

  void sendRefer(URI target, Map<String, dynamic> options) {
    logger.d('sendRefer()');

    List<dynamic> extraHeaders = Utils.cloneArray(options['extraHeaders']);
    EventManager eventHandlers = options['eventHandlers'] ?? EventManager();

    // Set event handlers.
    addAllEventHandlers(eventHandlers);

    // Replaces URI header field.

    String replaces = '';

    if (options['replaces'] != null) {
      replaces = options['replaces'].call_id;
      replaces += ';to-tag=${options['replaces'].to_tag}';
      replaces += ';from-tag=${options['replaces'].from_tag}';
      replaces = Uri.encodeComponent(replaces);
    }

    // Refer-To header field.
    String referTo =
        'Refer-To: <$target${replaces.isNotEmpty ? '?Replaces=$replaces' : ''}>';

    extraHeaders.add(referTo);

    // Referred-By header field.
    String referredBy =
        'Referred-By: <${_session.ua.configuration.uri.scheme}:${_session.ua.configuration.uri.user}@${_session.ua.configuration.uri.host}>';

    extraHeaders.add(referredBy);
    extraHeaders.add('Contact: ${_session.contact}');

    EventManager handlers = EventManager();
    handlers.on(EventOnSuccessResponse(), (EventOnSuccessResponse event) {
      _requestSucceeded(event.response);
    });
    handlers.on(EventOnErrorResponse(), (EventOnErrorResponse event) {
      _requestFailed(event.response, DartSIP_C.CausesType.REJECTED);
    });
    handlers.on(EventOnTransportError(), (EventOnTransportError event) {
      _requestFailed(null, DartSIP_C.CausesType.CONNECTION_ERROR);
    });
    handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout event) {
      _requestFailed(null, DartSIP_C.CausesType.REQUEST_TIMEOUT);
    });
    handlers.on(EventOnDialogError(), (EventOnDialogError event) {
      _requestFailed(null, DartSIP_C.CausesType.DIALOG_ERROR);
    });

    OutgoingRequest request = _session.sendRequest(
        SipMethod.REFER, <String, dynamic>{
      'extraHeaders': extraHeaders,
      'eventHandlers': handlers
    });

    _id = request.cseq;
  }

  void receiveNotify(IncomingRequest request) {
    logger.d('receiveNotify()');

    if (request.body == null) {
      return;
    }

    String status_line = request.body!.trim();
    dynamic parsed = Grammar.parse(status_line, 'Status_Line');

    if (parsed == -1) {
      logger
          .d('receiveNotify() | error parsing NOTIFY body: "${request.body}"');
      return;
    }

    String status_code = parsed.status_code.toString();
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

  void _requestSucceeded(IncomingMessage? response) {
    logger.d('REFER succeeded');

    logger.d('emit "requestSucceeded"');

    emit(EventReferRequestSucceeded(response: response));
  }

  void _requestFailed(IncomingMessage? response, dynamic cause) {
    logger.d('REFER failed');

    logger.d('emit "requestFailed"');

    emit(EventReferRequestFailed(response: response, cause: cause));
  }
}
