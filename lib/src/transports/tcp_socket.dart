import 'package:sip_ua/sip_ua.dart';
import 'package:sip_ua/src/transports/socket_interface.dart';
import 'package:sip_ua/src/transports/tcp_socket_impl.dart';
import '../grammar.dart';
import '../logger.dart';

import 'websocket_dart_impl.dart'
    if (dart.library.js) 'websocket_web_impl.dart';

class SIPUATcpSocket extends SIPUASocketInterface {
  SIPUATcpSocket(String host, String port,
      {required int messageDelay,
      TcpSocketSettings? tcpSocketSettings,
      int? weight})
      : _messageDelay = messageDelay {
    logger.d('new() [host:$host:$port]');
    String transport_scheme = 'tcp';
    _weight = weight;
    _host = host;
    _port = port;

    _sip_uri = 'sip:$host:$port;transport=$transport_scheme';
    logger.d('TCPC SIP URI: $_sip_uri');
    _via_transport = transport_scheme.toUpperCase();
    _tcpSocketSettings = tcpSocketSettings ?? TcpSocketSettings();
  }

  final int _messageDelay;

  String? _host;
  String? _port;
  String? _sip_uri;
  late String _via_transport;
  final String _tcp_socket_protocol = 'sip';
  SIPUATcpSocketImpl? _tcpSocketImpl;
  bool _closed = false;
  bool _connected = false;
  int? _weight;
  int? status;
  late TcpSocketSettings _tcpSocketSettings;

  @override
  String get via_transport => _via_transport;

  @override
  set via_transport(String value) {
    _via_transport = value.toUpperCase();
  }

  @override
  int? get weight => _weight;

  @override
  String? get sip_uri => _sip_uri;

  String? get host => _host;

  String? get port => _port;

  @override
  void connect() async {
    logger.d('connect()');

    if (_host == null) {
      throw AssertionError('Invalid argument: _host');
    }
    if (_port == null) {
      throw AssertionError('Invalid argument: _port');
    }

    if (_tcpSocketImpl != null) {
      disconnect();
    }
    logger.d('connecting to TcpSocket $_host:$_port');
    try {
      _tcpSocketImpl = SIPUATcpSocketImpl(
          _messageDelay, _host ?? '0.0.0.0', _port ?? '5060');

      _tcpSocketImpl!.onOpen = () {
        _closed = false;
        _connected = true;
        logger.d('Tcp Socket is now connected?');
        _onOpen();
      };

      _tcpSocketImpl!.onData = (dynamic data) {
        _onMessage(data);
      };

      _tcpSocketImpl!.onClose = (int? closeCode, String? closeReason) {
        logger.d('Closed [$closeCode, $closeReason]!');
        _connected = false;
        _onClose(true, closeCode, closeReason);
      };

      _tcpSocketImpl!.connect(
          protocols: <String>[_tcp_socket_protocol],
          tcpSocketSettings: _tcpSocketSettings);
    } catch (e, s) {
      logger.e(e.toString(), stackTrace: s);
      _connected = false;
      logger.e('TcpSocket error: $e');
    }
  }

  @override
  void disconnect() {
    logger.d('disconnect()');
    if (_closed) return;
    // Don't wait for the WebSocket 'close' event, do it now.
    _closed = true;
    _connected = false;
    _onClose(true, 0, 'Client send disconnect');
    try {
      if (_tcpSocketImpl != null) {
        _tcpSocketImpl!.close();
      }
    } catch (error) {
      logger.e('close() | error closing the TcpSocket: $error');
    }
  }

  @override
  bool send(dynamic message) {
    logger.d('send()');
    if (_closed) {
      throw 'transport closed';
    }
    try {
      _tcpSocketImpl!.send(message);
      return true;
    } catch (error) {
      logger.e('send() | error sending message: $error');
      throw error;
    }
  }

  @override
  bool isConnected() {
    return _connected;
  }

  /**
   * TcpSocket Event Handlers
   */
  void _onOpen() {
    logger.d('TcpSocket $_host:$port connected');
    onconnect!();
  }

  void _onClose(bool wasClean, int? code, String? reason) {
    logger.d('TcpSocket $_host:$port closed');
    if (wasClean == false) {
      logger.d('TcpSocket abrupt disconnection');
    }
    ondisconnect!(this, !wasClean, code, reason);
  }

  void _onMessage(dynamic data) {
    logger.d('Received TcpSocket data');
    if (data != null) {
      if (data.toString().trim().length > 0) {
        ondata!(data);
      } else {
        logger.d('Received and ignored empty packet');
      }
    }
  }

  @override
  bool isConnecting() {
    // TODO(cloudwebrtc): implement isConnecting
    throw UnimplementedError();
  }

  @override
  // TODO(cloudwebrtc): implement url
  String? get url => throw UnimplementedError();
}
