import 'dart:async';
import 'dart:math';

import './event_manager/events.dart';
import './transports/socket_interface.dart';
import 'exceptions.dart' as Exceptions;
import 'logger.dart';
import 'stack_trace_nj.dart';
import 'timers.dart';
import 'utils.dart';

enum TransportStatus { connected, connecting, disconnected }

enum SocketStatus { ready, error }

class SocketInfo {
  SocketInfo({
    required this.socket,
    required this.weight,
    required this.status,
  });

  SIPUASocketInterface socket;
  int weight;
  SocketStatus status;
}

const Map<String, int> defaultRecoveryOptions = <String, int>{
  'min_interval': 2, // minimum interval in seconds between recover attempts
  'max_interval': 30 // maximum interval in seconds between recover attempts
};

/*
 * Manages one or multiple DartSIP.Socket instances.
 * Is reponsible for transport recovery logic among all socket instances.
 *
 * @socket DartSIP::Socket instance
 */
class SocketTransport {
  SocketTransport(
    List<SIPUASocketInterface>? sockets, [
    Map<String, int> recovery_options = defaultRecoveryOptions,
  ]) {
    logger.d('Socket Transport new()');

    _recovery_options = recovery_options;

    // We must recieve at least 1 socket
    if (sockets!.isEmpty) {
      throw Exceptions.TypeError(
          'invalid argument: Must recieve atleast 1 web socket');
    }

    for (final SIPUASocketInterface socket in sockets) {
      _sockets.add(SocketInfo(
        socket: socket,
        weight: socket.weight ?? 0,
        status: SocketStatus.ready,
      ));
    }
    // Get the socket with higher weight.
    _getSocket();
  }

  TransportStatus status = TransportStatus.disconnected;
  // Current socket.
  late SIPUASocketInterface socket;
  // Socket collection.
  final List<SocketInfo> _sockets = <SocketInfo>[];
  late Map<String, int> _recovery_options;
  int _recover_attempts = 0;
  Timer? _recovery_timer;
  bool _close_requested = false;

  late void Function(SIPUASocketInterface? socket, int? attempts) onconnecting;
  late void Function(SIPUASocketInterface? socket, ErrorCause cause)
      ondisconnect;
  late void Function(SocketTransport transport) onconnect;
  late void Function(SocketTransport transport, String messageData) ondata;

  /**
   * Instance Methods
   */

  String get via_transport => socket.via_transport;

  String? get url => socket.url;

  String? get sip_uri => socket.sip_uri;

  void connect() {
    logger.d('Transport connect()');

    if (isConnected()) {
      logger.d('Transport is already connected');

      return;
    } else if (isConnecting()) {
      logger.d('Transport is connecting');

      return;
    }

    _close_requested = false;
    status = TransportStatus.connecting;
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
    logger.d('Transport close()');

    _close_requested = true;
    _recover_attempts = 0;
    status = TransportStatus.disconnected;

    // Clear recovery_timer.
    if (_recovery_timer != null) {
      clearTimeout(_recovery_timer);
      _recovery_timer = null;
    }

    // Unbind socket event callbacks.
    socket.onconnect = () => () {};
    socket.ondisconnect = (SIPUASocketInterface socket, bool error,
            int? closeCode, String? reason) =>
        () {};
    socket.ondata = (dynamic data) => () {};

    socket.disconnect();
    ondisconnect(
      socket,
      ErrorCause(
          cause: 'disconnect', status_code: 0, reason_phrase: 'close by local'),
    );
  }

  bool send(dynamic data) {
    logger.d('Socket Transport send()');

    if (!isConnected()) {
      logger.e(
          'unable to send message, transport is not connected. Current state is $status',
          stackTrace: StackTraceNJ());

      return false;
    }
    String message = data.toString();
    return socket.send(message);
  }

  bool isConnected() {
    return status == TransportStatus.connected;
  }

  bool isConnecting() {
    return status == TransportStatus.connecting;
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

    if (_sockets.isEmpty) {
      throw Exceptions.TypeError('invalid argument: too few sockets');
    }

    List<SocketInfo> candidates = <SocketInfo>[];

    for (final SocketInfo socket in _sockets) {
      if (socket.status == SocketStatus.error) {
        return; // continue the array iteration
      } else if (candidates.isEmpty) {
        candidates.add(socket);
      } else if (socket.weight > candidates[0].weight) {
        candidates = <SocketInfo>[socket];
      } else if (socket.weight == candidates[0].weight) {
        candidates.add(socket);
      }
    }

    if (candidates.isEmpty) {
      // All sockets have failed. reset sockets status.
      for (final SocketInfo socket in _sockets) {
        socket.status = SocketStatus.ready;
      }
      // Get next available socket.
      _getSocket();
      return;
    }

    num idx = (Math.randomDouble() * candidates.length).floor();

    socket = candidates[idx as int].socket;
  }

  /**
   * Socket Event Handlers
   */

  void _onConnect() {
    _recover_attempts = 0;
    status = TransportStatus.connected;

    // Clear recovery_timer.
    if (_recovery_timer != null) {
      clearTimeout(_recovery_timer);
      _recovery_timer = null;
    }
    onconnect(this);
  }

  void _onDisconnect(
      SIPUASocketInterface socket, bool error, int? closeCode, String? reason) {
    status = TransportStatus.disconnected;
    ondisconnect(
        socket,
        ErrorCause(
            cause: 'error', status_code: closeCode, reason_phrase: reason));

    if (_close_requested) {
      return;
    }
    // Update socket status.
    else {
      for (final SocketInfo s in _sockets) {
        if (socket == s.socket) {
          s.status = SocketStatus.error;
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
          ' message discarded',
        );
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
