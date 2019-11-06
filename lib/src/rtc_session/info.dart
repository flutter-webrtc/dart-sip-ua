import '../constants.dart';
import '../exceptions.dart' as Exceptions;
import '../rtc_session.dart' as RTCSession;
import '../utils.dart' as Utils;
import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../logger.dart';

class Info extends EventManager {
  var _session;
  var _direction;
  var _contentType;
  var _body;
  var request;
  final logger = Log();

  Info(session) {
    this._session = session;
    this._direction = null;
    this._contentType = null;
    this._body = null;
  }

  get contentType => this._contentType;

  get body => this._body;

  get direction => this._direction;

  send(contentType, body, options) {
    this._direction = 'outgoing';

    if (contentType == null) {
      throw new Exceptions.TypeError('Not enough arguments');
    }

    // Check RTCSession Status.
    if (this._session.status != RTCSession.C.STATUS_CONFIRMED &&
        this._session.status != RTCSession.C.STATUS_WAITING_FOR_ACK) {
      throw new Exceptions.InvalidStateError(this._session.status);
    }

    this._contentType = contentType;
    this._body = body;

    var extraHeaders = Utils.cloneArray(options['extraHeaders']);

    extraHeaders.add('Content-Type: ${contentType}');

    this._session.newInfo('local', this, this.request);

    EventManager handlers = EventManager();
    handlers.on(EventOnSuccessResponse(), (EventOnSuccessResponse event) {
      this.emit(EventSucceeded(originator: 'remote', response: event.response));
    });
    handlers.on(EventOnErrorResponse(), (EventOnErrorResponse event) {
      this.emit(
          EventCallFailed(originator: 'remote', response: event.response));
    });
    handlers.on(EventOnTransportError(), (EventOnTransportError event) {
      this._session.onTransportError();
    });
    handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout event) {
      this._session.onRequestTimeout();
    });
    handlers.on(EventOnDialogError(), (EventOnDialogError event) {
      this._session.onDialogError();
    });

    this._session.sendRequest(SipMethod.INFO, {
      'extraHeaders': extraHeaders,
      'eventHandlers': handlers,
      'body': body
    });
  }

  init_incoming(request) {
    this._direction = 'incoming';
    this.request = request;

    request.reply(200);

    this._contentType = request.getHeader('content-type');
    this._body = request.body;

    this._session.newInfo('remote', this, request);
  }
}
