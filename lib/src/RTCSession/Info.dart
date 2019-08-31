import 'package:events2/events2.dart';
import '../Constants.dart' as DartSIP_C;
import '../Exceptions.dart' as Exceptions;
import '../MediaSession.dart' as MediaSession;
import '../Utils.dart' as Utils;
import '../logger.dart';

class Info extends EventEmitter {
  var _session;
  var _direction;
  var _contentType;
  var _body;
  var request;
  final logger = Logger('RTCSession:Info');
  debug(msg) => logger.debug(msg);
  debugerror(error) => logger.error(error);

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
    if (this._session.status != MediaSession.C.STATUS_CONFIRMED &&
        this._session.status != MediaSession.C.STATUS_WAITING_FOR_ACK) {
      throw new Exceptions.InvalidStateError(this._session.status);
    }

    this._contentType = contentType;
    this._body = body;

    var extraHeaders = Utils.cloneArray(options.extraHeaders);

    extraHeaders.add('Content-Type: ${contentType}');

    this._session.newInfo(
        {'originator': 'local', 'info': this, 'request': this.request});

    this._session.sendRequest(DartSIP_C.INFO, {
      'extraHeaders': extraHeaders,
      'eventHandlers': {
        'onSuccessResponse': (response) {
          this.emit(
              'succeeded', {'originator': 'remote', 'response': response});
        },
        'onErrorResponse': (response) {
          this.emit('failed', {'originator': 'remote', 'response': response});
        },
        'onTransportError': () {
          this._session.onTransportError();
        },
        'onRequestTimeout': () {
          this._session.onRequestTimeout();
        },
        'onDialogError': () {
          this._session.onDialogError();
        }
      },
      'body': body
    });
  }

  init_incoming(request) {
    this._direction = 'incoming';
    this.request = request;

    request.reply(200);

    this._contentType = request.getHeader('content-type');
    this._body = request.body;

    this
        ._session
        .newInfo({'originator': 'remote', 'info': this, 'request': request});
  }
}
