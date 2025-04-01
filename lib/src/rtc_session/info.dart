import '../constants.dart';
import '../enums.dart';
import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../exceptions.dart' as Exceptions;
import '../rtc_session.dart';
import '../sip_message.dart';
import '../utils.dart' as utils;

class Info extends EventManager {
  Info(this._session);

  final RTCSession _session;
  Direction? _direction;
  String? _contentType;
  String? _body;
  IncomingRequest? _request;

  String? get contentType => _contentType;

  String? get body => _body;

  Direction? get direction => _direction;

  void send(String contentType, String body, Map<String, dynamic> options) {
    _direction = Direction.outgoing;

    if (contentType == null) {
      throw Exceptions.TypeError('Not enough arguments');
    }

    // Check RTCSession Status.
    if (_session.state != RtcSessionState.confirmed &&
        _session.state != RtcSessionState.waitingForAck) {
      throw Exceptions.InvalidStateError(_session.status);
    }

    _contentType = contentType;
    _body = body;

    List<dynamic> extraHeaders = utils.cloneArray(options['extraHeaders']);

    extraHeaders.add('Content-Type: $contentType');

    _session.newInfo(Originator.local, this, _request);

    EventManager handlers = EventManager();
    handlers.on(EventOnSuccessResponse(), (EventOnSuccessResponse event) {
      emit(EventSucceeded(
          originator: Originator.remote, response: event.response));
    });
    handlers.on(EventOnErrorResponse(), (EventOnErrorResponse event) {
      emit(EventCallFailed(
          originator: Originator.remote, response: event.response));
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
    _direction = Direction.incoming;
    _request = request;

    request.reply(200);

    _contentType = request.getHeader('content-type');
    _body = request.body;

    _session.newInfo(Originator.remote, this, request);
  }
}
