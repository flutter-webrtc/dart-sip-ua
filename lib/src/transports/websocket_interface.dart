import 'package:sip_ua/sip_ua.dart';

import '../grammar.dart';
import '../logger.dart';
import '../socket.dart';
import 'websocket_dart_impl.dart'
    if (dart.library.js) 'websocket_web_impl.dart';

class WebSocketInterface implements Socket {
  WebSocketInterface(String url, [WebSocketSettings webSocketSettings]) {
    logger.debug('new() [url:' + url + ']');
    _url = url;
    dynamic parsed_url = Grammar.parse(url, 'absoluteURI');
    if (parsed_url == -1) {
      logger.error('invalid WebSocket URI: $url');
      throw AssertionError('Invalid argument: $url');
    } else if (parsed_url.scheme != 'wss' && parsed_url.scheme != 'ws') {
      logger.error('invalid WebSocket URI scheme: ${parsed_url.scheme}');
      throw AssertionError('Invalid argument: $url');
    } else {
      String transport_scheme = webSocketSettings != null && webSocketSettings.transport_scheme != null
          ? webSocketSettings.transport_scheme.toLowerCase()
          : parsed_url.scheme;

      String port = parsed_url.port != null ? ':${parsed_url.port}' : '';
      _sip_uri = 'sip:${parsed_url.host}$port;transport=$transport_scheme';
      logger.debug('SIP URI: $_sip_uri');
      _via_transport = transport_scheme.toUpperCase();
    }
    _webSocketSettings = webSocketSettings ?? WebSocketSettings();
  }

  String _url;
  String _sip_uri;
  String _via_transport;
  final String _websocket_protocol = 'sip';
  WebSocketImpl _ws;
  bool _closed = false;
  bool _connected = false;
  int weight;
  int status;
  WebSocketSettings _webSocketSettings;

  @override
  void Function() onconnect;
  @override
  void Function(
          WebSocketInterface socket, bool error, int closeCode, String reason)
      ondisconnect;
  @override
  void Function(dynamic data) ondata;
  @override
  String get via_transport => _via_transport;

  @override
  set via_transport(String value) {
    _via_transport = value.toUpperCase();
  }

  @override
  String get sip_uri => _sip_uri;

  @override
  String get url => _url;

  @override
  void connect() async {
    logger.debug('connect()');
    if (isConnected()) {
      logger.debug('WebSocket $_url is already connected');
      return;
    } else if (isConnecting()) {
      logger.debug('WebSocket $_url is connecting');
      return;
    }
    if (_ws != null) {
      disconnect();
    }
    logger.debug('connecting to WebSocket $_url');
    try {
      _ws = WebSocketImpl(_url);

      _ws.onOpen = () {
        _closed = false;
        _connected = true;
        logger.debug('Web Socket is now connected');
        _onOpen();
      };

      _ws.onMessage = (dynamic data) {
        _onMessage(data);
      };

      _ws.onClose = (int closeCode, String closeReason) {
        logger.debug('Closed [$closeCode, $closeReason]!');
        _connected = false;
        _onClose(true, closeCode, closeReason);
      };

      _ws.connect(
          protocols: <String>[_websocket_protocol],
          webSocketSettings: _webSocketSettings);
    } catch (e, s) {
      Log.e(e.toString(), null, s);
      _connected = false;
      logger.error('WebSocket $_url error: $e');
    }
  }

  @override
  void disconnect() {
    logger.debug('disconnect()');
    if (_closed) return;
    // Don't wait for the WebSocket 'close' event, do it now.
    _closed = true;
    _connected = false;
    _onClose(true, 0, 'Client send disconnect');
    try {
      if (_ws != null) {
        _ws.close();
      }
    } catch (error) {
      logger
          .error('close() | error closing the WebSocket: ' + error.toString());
    }
  }

  @override
  bool send(dynamic message) {
    logger.debug('send()');
    if (_closed) {
      throw 'transport closed';
    }
    try {
      _ws.send(message);
      return true;
    } catch (error) {
      logger.error('send() | error sending message: ' + error.toString());
      throw error;
    }
  }

  bool isConnected() {
    return _connected;
  }

  bool isConnecting() {
    return _ws != null && _ws.isConnecting();
  }

  /**
   * WebSocket Event Handlers
   */
  void _onOpen() {
    logger.debug('WebSocket $_url connected');
    onconnect();
  }

  void _onClose(bool wasClean, int code, String reason) {
    logger.debug('WebSocket $_url closed');
    if (wasClean == false) {
      logger.debug('WebSocket abrupt disconnection');
    }
    ondisconnect(this, !wasClean, code, reason);
  }

  void _onMessage(dynamic data) {
    logger.debug('Received WebSocket message');
    if (data != null) {
      if (data.toString().trim().length > 0) {
        ondata(data);
      } else {
        logger.debug('Received and ignored empty packet');
      }
    }
  }
}
