import 'package:sip_ua/src/name_addr_header.dart';
import 'constants.dart' as DartSIP_C;
import 'constants.dart';
import 'event_manager/event_manager.dart';
import 'event_manager/internal_events.dart';
import 'exceptions.dart' as Exceptions;
import 'logger.dart';
import 'request_sender.dart';
import 'sip_message.dart';
import 'ua.dart';
import 'uri.dart';
import 'utils.dart' as Utils;

class Message extends EventManager with Applicant {
  Message(UA ua) {
    _ua = ua;
    _request = null;
    _closed = false;

    _direction = null;
    _local_identity = null;
    _remote_identity = null;

    // Whether an incoming message has been replied.
    _is_replied = false;

    // Custom message empty object for high level use.
    _data = <String, dynamic>{};
  }

  UA? _ua;
  dynamic _request;
  bool? _closed;
  String? _direction;
  NameAddrHeader? _local_identity;
  NameAddrHeader? _remote_identity;
  bool? _is_replied;
  Map<String, dynamic>? _data;
  String? get direction => _direction;

  NameAddrHeader? get local_identity => _local_identity;

  NameAddrHeader? get remote_identity => _remote_identity;

  Map<String, dynamic>? get data => _data;

  void send(String target, String body, [Map<String, dynamic>? options]) {
    String originalTarget = target;
    options = options ?? <String, dynamic>{};

    if (target == null || body == null) {
      throw Exceptions.TypeError('Not enough arguments');
    }

    // Check target validity.
    URI? normalized = _ua!.normalizeTarget(target);
    if (normalized == null) {
      throw Exceptions.TypeError('Invalid target: $originalTarget');
    }

    // Get call options.
    List<dynamic> extraHeaders = Utils.cloneArray(options['extraHeaders']);
    EventManager eventHandlers = options['eventHandlers'] ?? EventManager();
    String contentType = options['contentType'] ?? 'text/plain';

    // Set event handlers.
    addAllEventHandlers(eventHandlers);

    extraHeaders.add('Content-Type: $contentType');

    _request =
        OutgoingRequest(SipMethod.MESSAGE, normalized, _ua, null, extraHeaders);
    if (body != null) {
      _request.body = body;
    }

    EventManager handlers = EventManager();
    handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout value) {
      _onRequestTimeout();
    });
    handlers.on(EventOnTransportError(), (EventOnTransportError value) {
      _onTransportError();
    });
    handlers.on(EventOnReceiveResponse(), (EventOnReceiveResponse event) {
      _receiveResponse(event.response);
    });

    RequestSender request_sender = RequestSender(_ua!, _request, handlers);

    _newMessage('local', _request);

    request_sender.send();
  }

  void init_incoming(IncomingRequest request) {
    _request = request;

    _newMessage('remote', request);

    // Reply with a 200 OK if the user didn't reply.
    if (_is_replied == null) {
      _is_replied = true;
      request.reply(200);
    }

    close();
  }

  /*
   * Accept the incoming Message
   * Only valid for incoming Messages
   */
  void accept(Map<String, dynamic> options) {
    List<dynamic> extraHeaders = Utils.cloneArray(options['extraHeaders']);
    String? body = options['body'];

    if (_direction != 'incoming') {
      throw Exceptions.NotSupportedError(
          '"accept" not supported for outgoing Message');
    }

    if (_is_replied != null) {
      throw AssertionError('incoming Message already replied');
    }

    _is_replied = true;
    _request.reply(200, null, extraHeaders, body);
  }

  /**
   * Reject the incoming Message
   * Only valid for incoming Messages
   */
  void reject(Map<String, dynamic> options) {
    int status_code = options['status_code'] ?? 480;
    String? reason_phrase = options['reason_phrase'];
    List<dynamic> extraHeaders = Utils.cloneArray(options['extraHeaders']);
    String? body = options['body'];

    if (_direction != 'incoming') {
      throw Exceptions.NotSupportedError(
          '"reject" not supported for outgoing Message');
    }

    if (_is_replied != null) {
      throw AssertionError('incoming Message already replied');
    }

    if (status_code < 300 || status_code >= 700) {
      throw Exceptions.TypeError('Invalid status_code: $status_code');
    }

    _is_replied = true;
    _request.reply(status_code, reason_phrase, extraHeaders, body);
  }

  void _receiveResponse(IncomingResponse? response) {
    if (_closed != null) {
      return;
    }
    if (RegExp(r'^1[0-9]{2}$').hasMatch(response!.status_code)) {
      // Ignore provisional responses.
    } else if (RegExp(r'^2[0-9]{2}$').hasMatch(response.status_code)) {
      _succeeded('remote', response);
    } else {
      String cause = Utils.sipErrorCause(response.status_code);
      _failed('remote', response.status_code, cause, response.reason_phrase);
    }
  }

  void _onRequestTimeout() {
    if (_closed != null) {
      return;
    }
    _failed(
        'system', 408, DartSIP_C.CausesType.REQUEST_TIMEOUT, 'Request Timeout');
  }

  void _onTransportError() {
    if (_closed != null) {
      return;
    }
    _failed('system', 500, DartSIP_C.CausesType.CONNECTION_ERROR,
        'Transport Error');
  }

  @override
  void close() {
    _closed = true;
    _ua!.destroyMessage(this);
  }

  /**
   * Internal Callbacks
   */

  void _newMessage(String originator, dynamic request) {
    if (originator == 'remote') {
      _direction = 'incoming';
      _local_identity = request.to;
      _remote_identity = request.from;
    } else if (originator == 'local') {
      _direction = 'outgoing';
      _local_identity = request.from;
      _remote_identity = request.to;
    }

    _ua!.newMessage(this, originator, request);
  }

  void _failed(String originator, int? status_code, String cause,
      String? reason_phrase) {
    logger.d('MESSAGE failed');
    close();
    logger.d('emit "failed"');
    emit(EventCallFailed(
        originator: originator,
        cause: ErrorCause(
            cause: cause,
            status_code: status_code,
            reason_phrase: reason_phrase)));
  }

  void _succeeded(String originator, IncomingResponse? response) {
    logger.d('MESSAGE succeeded');

    close();

    logger.d('emit "succeeded"');

    emit(EventSucceeded(originator: originator, response: response));
  }
}
