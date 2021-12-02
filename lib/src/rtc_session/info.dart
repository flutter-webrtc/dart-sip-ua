import 'package:sip_ua/src/sip_message.dart';
import '../constants.dart';
import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../exceptions.dart' as Exceptions;
import '../rtc_session.dart' as rtc;
import '../utils.dart' as utils;

class Info extends EventManager {
  Info(this._session);

  final rtc.RTCSession _session;
  String? _direction;
  String? _contentType;
  String? _body;
  IncomingRequest? _request;

  String? get contentType => _contentType;

  String? get body => _body;

  String? get direction => _direction;

  void send(String contentType, String body, Map<String, dynamic> options) {
    _direction = 'outgoing';

    if (contentType == null) {
      throw Exceptions.TypeError('Not enough arguments');
    }

    // Check RTCSession Status.
    if (_session.status != rtc.C.STATUS_CONFIRMED &&
        _session.status != rtc.C.STATUS_WAITING_FOR_ACK) {
      throw Exceptions.InvalidStateError(_session.status);
    }

    _contentType = contentType;
    _body = body;

    List<dynamic> extraHeaders = utils.cloneArray(options['extraHeaders']);

    extraHeaders.add('Content-Type: $contentType');

    _session.newInfo('local', this, _request);

    EventManager handlers = EventManager();
    handlers.on(EventOnSuccessResponse(), (EventOnSuccessResponse event) {
      emit(EventSucceeded(originator: 'remote', response: event.response));
    });
    handlers.on(EventOnErrorResponse(), (EventOnErrorResponse event) {
      emit(EventCallFailed(originator: 'remote', response: event.response));
    });
    handlers.on(EventOnTransportError(), (EventOnTransportError event) {
      _session.onTransportError();
    });
    handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout event) {
      _session.onRequestTimeout();
    });
    handlers.on(EventOnDialogError(), (EventOnDialogError event) {
      _session.onDialogError();
    });

    _session.sendRequest(SipMethod.INFO, <String, dynamic>{
      'extraHeaders': extraHeaders,
      'eventHandlers': handlers,
      'body': body
    });
  }

  void init_incoming(IncomingRequest request) {
    _direction = 'incoming';
    _request = request;

    request.reply(200);

    _contentType = request.getHeader('content-type');
    _body = request.body;

    _session.newInfo('remote', this, request);
  }
}
