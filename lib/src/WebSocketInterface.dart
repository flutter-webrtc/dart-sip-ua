import 'dart:io';
import 'Socket.dart';
import 'logger.dart';
import 'Grammar.dart';

class WebSocketInterface implements Socket {
  final logger = Logger('WebSocketInterface');
  String _url;
  String _sip_uri;
  String _via_transport;
  var _ws;
  var _closed = false;
  var _connected = false;
  var weight;

  @override
  dynamic onconnect;
  @override
  dynamic ondisconnect;
  @override
  dynamic ondata;

  WebSocketInterface(url) {
    debug('new() [url:' + url + ']');
    this._url = url;
    var parsed_url = Grammar.parse(url, 'absoluteURI');
    if (parsed_url == -1) {
      debugerror('invalid WebSocket URI: ${url}');
      throw new AssertionError('Invalid argument: ${url}');
    } else if (parsed_url.scheme != 'wss' && parsed_url.scheme != 'ws') {
      debugerror('invalid WebSocket URI scheme: ${parsed_url.scheme}');
      throw new AssertionError('Invalid argument: ${url}');
    } else {
      var port = parsed_url.port != null ? ':${parsed_url.port}' : '';
      this._sip_uri = 'sip:${parsed_url.host}${port};transport=ws';
      debug('SIP URI: ${this._sip_uri}');
      this._via_transport = parsed_url.scheme.toUpperCase();
    }
  }
  debug(msg) => logger.debug(msg);

  debugerror(error) => logger.error(error);

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
    debug('connect()');
    if (this.isConnected()) {
      debug('WebSocket ${this._url} is already connected');
      return;
    } else if (this.isConnecting()) {
      debug('WebSocket ${this._url} is connecting');
      return;
    }
    if (this._ws != null) {
      this.disconnect();
    }
    debug('connecting to WebSocket ${this._url}');
    try {
      this._ws = await WebSocket.connect(this._url, headers: {
        'Sec-WebSocket-Protocol': 'sip',
      });
      this._ws.listen((data) {
        this._onMessage(data);
      }, onDone: () {
        logger.debug('Closed by server!');
        _connected = false;
        this._onClose(true, 0, 'Closed by server!');
      });
      _connected = true;
      this._onOpen();
    } catch (e) {
      _connected = false;
      this._onError(e.toString());
    }
  }

  @override
  disconnect() {
    debug('disconnect()');
    if (this._closed) return;
    // Don't wait for the WebSocket 'close' event, do it now.
    this._closed = true;
    this._connected = false;
    this._onClose(true, 0, "Client send disconnect");
    try {
      this._ws.close();
    } catch (error) {
      debugerror('close() | error closing the WebSocket: ' + error);
    }
  }

  @override
  send(message) {
    debug('send()');
    if (this._closed) {
      throw 'transport closed';
    }
    try {
      this._ws.add(message);
      return true;
    } catch (error) {
      logger.failure('send() | error sending message: ' + error.toString());
      throw error;
    }
  }

  isConnected() {
    return _connected;
  }

  isConnecting() {
    return false; // TODO: this._ws && this._ws.readyState == this._ws.CONNECTING;
  }

  /**
   * WebSocket Event Handlers
   */
  _onOpen() {
    debug('WebSocket ${this._url} connected');
    this.onconnect();
  }

  _onClose(wasClean, code, reason) {
    debug('WebSocket ${this._url} closed');
    if (wasClean == false) {
      debug('WebSocket abrupt disconnection');
    }
    var data = {
      'socket': this,
      'error': !wasClean,
      'code': code,
      'reason': reason
    };
    this.ondisconnect(data);
  }

  _onMessage(data) {
    debug('Received WebSocket message');
    this.ondata(data);
  }

  _onError(e) {
    debugerror('WebSocket ${this._url} error: ${e}');
  }
}
