import 'package:events2/events2.dart';

import '../sip_ua.dart';
import 'Constants.dart' as DartSIP_C;
import 'Constants.dart';
import 'Exceptions.dart' as Exceptions;
import 'RequestSender.dart';
import 'SIPMessage.dart' as SIPMessage;
import 'Utils.dart' as Utils;
import 'logger.dart';

class Message extends EventEmitter {
  UA _ua;
  var _request;
  var _closed;
  var _direction;
  var _local_identity;
  var _remote_identity;
  var _is_replied;
  var _data;
  final logger = new Logger('Message');
  debug(msg) => logger.debug(msg);
  debugerror(error) => logger.error(error);

  Message(UA ua) {
    this._ua = ua;
    this._request = null;
    this._closed = false;

    this._direction = null;
    this._local_identity = null;
    this._remote_identity = null;

    // Whether an incoming message has been replied.
    this._is_replied = false;

    // Custom message empty object for high level use.
    this._data = {};
  }

  get direction => this._direction;

  get local_identity => this._local_identity;

  get remote_identity => this._remote_identity;

  get data => this._data;

  send(target, body, [options]) {
    var originalTarget = target;
    options = options ?? {};

    if (target == null || body == null) {
      throw new Exceptions.TypeError('Not enough arguments');
    }

    // Check target validity.
    target = this._ua.normalizeTarget(target);
    if (target == null) {
      throw new Exceptions.TypeError('Invalid target: ${originalTarget}');
    }

    // Get call options.
    var extraHeaders = Utils.cloneArray(options['extraHeaders']);
    var eventHandlers = options['eventHandlers'] ?? {};
    var contentType = options['contentType'] ?? 'text/plain';

    // Set event handlers.
    for (var event in eventHandlers) {
      if (eventHandlers.containsKey(event)) {
        this.on(event, eventHandlers[event]);
      }
    }

    extraHeaders.add('Content-Type: $contentType');

    this._request = new SIPMessage.OutgoingRequest(
        SipMethod.MESSAGE, target, this._ua, null, extraHeaders);
    if (body != null) {
      this._request.body = body;
    }

    var request_sender = new RequestSender(this._ua, this._request, {
      'onRequestTimeout': () => () {
            this._onRequestTimeout();
          },
      'onTransportError': () => () {
            this._onTransportError();
          },
      'onReceiveResponse': (response) => () {
            this._receiveResponse(response);
          }
    });

    this._newMessage('local', this._request);

    request_sender.send();
  }

  init_incoming(request) {
    this._request = request;

    this._newMessage('remote', request);

    // Reply with a 200 OK if the user didn't reply.
    if (this._is_replied == null) {
      this._is_replied = true;
      request.reply(200);
    }

    this.close();
  }

  /*
   * Accept the incoming Message
   * Only valid for incoming Messages
   */
  accept(options) {
    var extraHeaders = Utils.cloneArray(options['extraHeaders']);
    var body = options['body'];

    if (this._direction != 'incoming') {
      throw new Exceptions.NotSupportedError(
          '"accept" not supported for outgoing Message');
    }

    if (this._is_replied != null) {
      throw new AssertionError('incoming Message already replied');
    }

    this._is_replied = true;
    this._request.reply(200, null, extraHeaders, body);
  }

  /**
   * Reject the incoming Message
   * Only valid for incoming Messages
   */
  reject(options) {
    var status_code = options['status_code'] ?? 480;
    var reason_phrase = options['reason_phrase'];
    var extraHeaders = Utils.cloneArray(options['extraHeaders']);
    var body = options['body'];

    if (this._direction != 'incoming') {
      throw new Exceptions.NotSupportedError(
          '"reject" not supported for outgoing Message');
    }

    if (this._is_replied != null) {
      throw new AssertionError('incoming Message already replied');
    }

    if (status_code < 300 || status_code >= 700) {
      throw new Exceptions.TypeError('Invalid status_code: $status_code');
    }

    this._is_replied = true;
    this._request.reply(status_code, reason_phrase, extraHeaders, body);
  }

  _receiveResponse(response) {
    if (this._closed != null) {
      return;
    }
    if (RegExp(r'^1[0-9]{2}$').hasMatch(response.status_code)) {
      // Ignore provisional responses.
    } else if (RegExp(r'^2[0-9]{2}$').hasMatch(response.status_code)) {
      this._succeeded('remote', response);
    } else {
      var cause = Utils.sipErrorCause(response.status_code);

      this._failed('remote', response, cause);
    }
  }

  _onRequestTimeout() {
    if (this._closed != null) {
      return;
    }
    this._failed('system', null, DartSIP_C.causes.REQUEST_TIMEOUT);
  }

  _onTransportError() {
    if (this._closed != null) {
      return;
    }
    this._failed('system', null, DartSIP_C.causes.CONNECTION_ERROR);
  }

  close() {
    this._closed = true;
    this._ua.destroyMessage(this);
  }

  /**
   * Internal Callbacks
   */

  _newMessage(originator, request) {
    if (originator == 'remote') {
      this._direction = 'incoming';
      this._local_identity = request.to;
      this._remote_identity = request.from;
    } else if (originator == 'local') {
      this._direction = 'outgoing';
      this._local_identity = request.from;
      this._remote_identity = request.to;
    }

    this._ua.newMessage(
        this, {'originator': originator, 'message': this, 'request': request});
  }

  _failed(originator, response, cause) {
    debug('MESSAGE failed');

    this.close();

    debug('emit "failed"');

    this.emit('failed', {
      'originator': originator,
      'response': response ?? null,
      'cause': cause
    });
  }

  _succeeded(originator, response) {
    debug('MESSAGE succeeded');

    this.close();

    debug('emit "succeeded"');

    this.emit('succeeded', {'originator': originator, 'response': response});
  }
}
