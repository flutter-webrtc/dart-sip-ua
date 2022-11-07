import 'dart:async';
import 'dart:math';

import 'package:sip_ua/src/event_manager/events.dart';
import 'exceptions.dart' as Exceptions;
import 'logger.dart';
import 'socket.dart' as Socket;
import 'stack_trace_nj.dart';
import 'timers.dart';
import 'transports/websocket_interface.dart';
import 'utils.dart';

/**
 * Constants
 */
class C {
  // Transport status.
  static const int STATUS_CONNECTED = 0;
  static const int STATUS_CONNECTING = 1;
  static const int STATUS_DISCONNECTED = 2;

  // Socket status.
  static const int SOCKET_STATUS_READY = 0;
  static const int SOCKET_STATUS_ERROR = 1;

  // Recovery options.
  static const Map<String, int> recovery_options = <String, int>{
    'min_interval': 2, // minimum interval in seconds between recover attempts
    'max_interval': 30 // maximum interval in seconds between recover attempts
  };
}

/*
 * Manages one or multiple DartSIP.Socket instances.
 * Is reponsible for transport recovery logic among all socket instances.
 *
 * @socket DartSIP::Socket instance
 */
class Transport {
  Transport(List<WebSocketInterface> sockets,
      [Map<String, int> recovery_options = C.recovery_options]) {
    logger.d('new()');

    _recovery_options = recovery_options;

    // We must recieve at least 1 socket
    if (sockets.length == 0) {
      throw Exceptions.TypeError('invalid argument: sockets');
    }

    for (WebSocketInterface socket in sockets) {
      _socketsMap.add(<String, dynamic>{
        'socket': socket,
        'weight': socket.weight ?? 0,
        'status': C.SOCKET_STATUS_READY
      });
    }

    // Get the socket with higher weight.
    _getSocket();
  }

  int status = C.STATUS_DISCONNECTED;
  // Current socket.
  late WebSocketInterface socket;
  // Socket collection.
  final List<Map<String, dynamic>> _socketsMap = <Map<String, dynamic>>[];
  late Map<String, int> _recovery_options;
  int _recover_attempts = 0;
  Timer? _recovery_timer;
  bool _close_requested = false;

  late void Function(WebSocketInterface? socket, int? attempts) onconnecting;
  late void Function(WebSocketInterface? socket, ErrorCause cause) ondisconnect;
  late void Function(Transport transport) onconnect;
  late void Function(Transport transport, String messageData) ondata;

  /**
   * Instance Methods
   */

  String get via_transport => socket.via_transport;

  String? get url => socket.url;

  String? get sip_uri => socket.sip_uri;

  void connect() {
    logger.d('connect()');

    if (isConnected()) {
      logger.d('Transport is already connected');

      return;
    } else if (isConnecting()) {
      logger.d('Transport is connecting');

      return;
    }

    _close_requested = false;
    status = C.STATUS_CONNECTING;
    onconnecting(socket, _recover_attempts);

    if (!_close_requested) {
      // Bind socket event callbacks.
      socket.onconnect = _onConnect;
      socket.ondisconnect = _onDisconnect;
      socket.ondata = _onData;
      socket.connect();
    }
    return;
  }

  void disconnect() {
    logger.d('close()');

    _close_requested = true;
    _recover_attempts = 0;
    status = C.STATUS_DISCONNECTED;

    // Clear recovery_timer.
    if (_recovery_timer != null) {
      clearTimeout(_recovery_timer);
      _recovery_timer = null;
    }

    // Unbind socket event callbacks.
    socket.onconnect = () => () {};
    socket.ondisconnect = (WebSocketInterface socket, bool error,
            int? closeCode, String? reason) =>
        () {};
    socket.ondata = (dynamic data) => () {};

    socket.disconnect();
    ondisconnect(
        socket,
        ErrorCause(
            cause: 'disconnect',
            status_code: 0,
            reason_phrase: 'close by local'));
  }

  bool send(dynamic data) {
    logger.d('send()');

    if (!isConnected()) {
      logger.e(
          'unable to send message, transport is not connected. Current state is $status',
          null,
          StackTraceNJ());
      return false;
    }

    String message = data.toString();
    //logger.d('sending message:\n\n$message\n');
    return socket.send(message);
  }

  bool isConnected() {
    return status == C.STATUS_CONNECTED;
  }

  bool isConnecting() {
    return status == C.STATUS_CONNECTING;
  }

  /**
   * Private API.
   */

  void _reconnect(bool error) {
    _recover_attempts = _recover_attempts + 1;

    num k = ((Math.randomDouble() * pow(2, _recover_attempts)) + 1).floor();

    if (k < _recovery_options['min_interval']!) {
      k = _recovery_options['min_interval']!;
    } else if (k > _recovery_options['max_interval']!) {
      k = _recovery_options['max_interval']!;
    }

    logger.d(
        'reconnection attempt: $_recover_attempts. next connection attempt in $k seconds');

    _recovery_timer = setTimeout(() {
      if (!_close_requested && !(isConnected() || isConnecting())) {
        // Get the next available socket with higher weight.
        _getSocket();
        // Connect the socket.
        connect();
      }
    }, k * 1000 as int);
  }

  /**
   * get the next available socket with higher weight
   */
  void _getSocket() {
    // If we dont have at least 1 socket to try and use, thiw will loop endlessly

    if (_socketsMap.length == 0) {
      throw Exceptions.TypeError('invalid argument: too few sockets');
    }

    List<Map<String, dynamic>> candidates = <Map<String, dynamic>>[];

    for (Map<String, dynamic> socket in _socketsMap) {
      if (socket['status'] == C.SOCKET_STATUS_ERROR) {
        return; // continue the array iteration
      } else if (candidates.isEmpty) {
        candidates.add(socket);
      } else if (socket['weight'] > candidates[0]['weight']) {
        candidates = <Map<String, dynamic>>[socket];
      } else if (socket['weight'] == candidates[0]['weight']) {
        candidates.add(socket);
      }
    }

    if (candidates.isEmpty) {
      // All sockets have failed. reset sockets status.
      for (Map<String, dynamic> socket in _socketsMap) {
        socket['status'] = C.SOCKET_STATUS_READY;
      }
      // Get next available socket.
      _getSocket();
      return;
    }

    num idx = (Math.randomDouble() * candidates.length).floor();

    socket = candidates[idx as int]['socket'];
  }

  /**
   * Socket Event Handlers
   */

  void _onConnect() {
    _recover_attempts = 0;
    status = C.STATUS_CONNECTED;

    // Clear recovery_timer.
    if (_recovery_timer != null) {
      clearTimeout(_recovery_timer);
      _recovery_timer = null;
    }
    onconnect(this);
  }

  void _onDisconnect(
      WebSocketInterface socket, bool error, int? closeCode, String? reason) {
    status = C.STATUS_DISCONNECTED;
    ondisconnect(
        socket,
        ErrorCause(
            cause: 'error', status_code: closeCode, reason_phrase: reason));

    if (_close_requested) {
      return;
    }
    // Update socket status.
    else {
      for (Map<String, dynamic> socket in _socketsMap) {
        if (socket == socket['socket']) {
          socket['status'] = C.SOCKET_STATUS_ERROR;
        }
      }
    }

    _reconnect(error);
  }

  void _onData(dynamic data) {
    // CRLF Keep Alive response from server. Ignore it.
    if (data == '\r\n') {
      logger.d('received message with CRLF Keep Alive response');
      return;
    }
    // Binary message.
    else if (data is! String) {
      try {
        data = String.fromCharCodes(data);
      } catch (evt) {
        logger.d(
            'received binary message [${data.runtimeType}]failed to be converted into string,'
            ' message discarded');
        return;
      }

      logger.d('received binary message:\n\n$data\n');
    }

    // Text message.
    else {
      logger.d('received text message:\n\n$data\n');
    }

    ondata(this, data);
  }
}
