import 'dart:async';
import 'dart:convert';
import 'websocket_dart_impl.dart'
    if (dart.library.js) 'websocket_web_impl.dart';
import 'dart:math';

import '../grammar.dart';
import '../socket.dart';
import '../timers.dart';
import '../logger.dart';

class WebSocketInterface implements Socket {
  String _url;
  String _sip_uri;
  String _via_transport;
  String _websocket_protocol = 'sip';
  bool _allowBadCertificate = false;
  WebSocketImpl _ws;
  var _closed = false;
  var _connected = false;
  var weight;
  Map<String, dynamic> _wsExtraHeaders;

  final logger = Log();
  @override
  void Function() onconnect;
  @override
  void Function(
          WebSocketInterface socket, bool error, int closeCode, String reason)
      ondisconnect;
  @override
  void Function(dynamic data) ondata;

  WebSocketInterface(String url,
      [Map<String, dynamic> wsExtraHeaders, bool allowBadCertificate]) {
    logger.debug('new() [url:' + url + ']');
    this._url = url;
    var parsed_url = Grammar.parse(url, 'absoluteURI');
    if (parsed_url == -1) {
      logger.error('invalid WebSocket URI: ${url}');
      throw new AssertionError('Invalid argument: ${url}');
    } else if (parsed_url.scheme != 'wss' && parsed_url.scheme != 'ws') {
      logger.error('invalid WebSocket URI scheme: ${parsed_url.scheme}');
      throw new AssertionError('Invalid argument: ${url}');
    } else {
      var port = parsed_url.port != null ? ':${parsed_url.port}' : '';
      this._sip_uri =
          'sip:${parsed_url.host}${port};transport=${parsed_url.scheme}';
      logger.debug('SIP URI: ${this._sip_uri}');
      this._via_transport = parsed_url.scheme.toUpperCase();
    }
    this._wsExtraHeaders = wsExtraHeaders ?? {};
    this._allowBadCertificate = allowBadCertificate ?? false;
  }

  @override
  get via_transport => this._via_transport;

  set via_transport(value) {
    this._via_transport = value.toUpperCase();
  }

  @override
  get sip_uri => this._sip_uri;

  @override
  get url => this._url;

  @override
  connect() async {
    logger.debug('connect()');
    if (this.isConnected()) {
      logger.debug('WebSocket ${this._url} is already connected');
      return;
    } else if (this.isConnecting()) {
      logger.debug('WebSocket ${this._url} is connecting');
      return;
    }
    if (this._ws != null) {
      this.disconnect();
    }
    logger.debug('connecting to WebSocket ${this._url}');
    try {
      this._ws = WebSocketImpl(this._url);

      this._ws.onOpen = () {
        _closed = false;
        _connected = true;
        logger.debug("Web Socket is now connected");
        this._onOpen();
      };

      this._ws.onMessage = (data) {
        this._onMessage(data);
      };

      this._ws.onClose = (closeCode, closeReason) {
        logger.debug('Closed [${closeCode}, ${closeReason}]!');
        _connected = false;
        this._onClose(true, closeCode, closeReason);
      };

      await this._ws.connect(extHeaders: {
        'Sec-WebSocket-Protocol': _websocket_protocol,
        ...this._wsExtraHeaders
      }, allowBadCertificate: this._allowBadCertificate);
    } catch (e, s) {
      Log.e(e.toString(), null, s);
      _connected = false;
      this._onError(e.toString());
    }
  }

  @override
  disconnect() {
    logger.debug('disconnect()');
    if (this._closed) return;
    // Don't wait for the WebSocket 'close' event, do it now.
    this._closed = true;
    this._connected = false;
    this._onClose(true, 0, "Client send disconnect");
    try {
      if (this._ws != null) {
        this._ws.close();
      }
    } catch (error) {
      logger
          .error('close() | error closing the WebSocket: ' + error.toString());
    }
  }

  @override
  bool send(message) {
    logger.debug('send()');
    if (this._closed) {
      throw 'transport closed';
    }
    try {
      this._ws.send(message);
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
    return this._ws != null && this._ws.isConnecting();
  }

  /**
   * WebSocket Event Handlers
   */
  void _onOpen() {
    logger.debug('WebSocket ${this._url} connected');
    this.onconnect();
  }

  void _onClose(wasClean, code, reason) {
    logger.debug('WebSocket ${this._url} closed');
    if (wasClean == false) {
      logger.debug('WebSocket abrupt disconnection');
    }
    this.ondisconnect(this, !wasClean, code, reason);
  }

  void _onMessage(data) {
    logger.debug('Received WebSocket message');
    if (data != null) {
      if (data.toString().trim().length > 0) {
        this.ondata(data);
      } else {
        logger.debug("Received and ignored empty packet");
      }
    }
  }

  void _onError(e) {
    logger.error('WebSocket ${this._url} error: ${e}');
  }
}
