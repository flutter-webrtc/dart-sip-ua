import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:async';
import '../logger.dart';
import '../grammar.dart';

typedef void OnMessageCallback(dynamic msg);
typedef void OnCloseCallback(int code, String reason);
typedef void OnOpenCallback();

class WebSocketImpl {
  String _url;
  WebSocket _socket;
  final logger = Log();
  OnOpenCallback onOpen;
  OnMessageCallback onMessage;
  OnCloseCallback onClose;
  WebSocketImpl(this._url);

  void connect(
      {Iterable<String> protocols,
      Map<String, String> extHeaders,
      bool allowBadCertificate = false}) async {
    logger.info('connect $_url, $extHeaders, $protocols');
    try {
      if (allowBadCertificate) {
        /// Allow self-signed certificate, for test only.
        var parsed_url = Grammar.parse(_url, 'absoluteURI');
        _socket = await _connectForBadCertificate(
            parsed_url.scheme, parsed_url.host, parsed_url.port, extHeaders);
      } else {
        _socket = await WebSocket.connect(_url,
            protocols: protocols, headers: extHeaders);
      }

      this?.onOpen();
      _socket.listen((data) {
        this?.onMessage(data);
      }, onDone: () {
        this?.onClose(_socket.closeCode, _socket.closeReason);
      });
    } catch (e) {
      this.onClose(500, e.toString());
    }
  }

  void send(data) {
    if (_socket != null) {
      _socket.add(data);
      logger.debug('send: \n\n$data');
    }
  }

  void close() {
    _socket.close();
  }

  bool isConnecting() {
    return _socket != null && _socket.readyState == WebSocket.connecting;
  }

  /// For test only.
  Future<WebSocket> _connectForBadCertificate(String scheme, String host,
      int port, Map<String, String> extHeaders) async {
    try {
      var r = new Random();
      var key = base64.encode(List<int>.generate(8, (_) => r.nextInt(255)));
      var securityContext = new SecurityContext();
      var client = HttpClient(context: securityContext);
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        logger.warn('Allow self-signed certificate => $host:$port. ');
        return true;
      };

      var request = await client.getUrl(Uri.parse(
          (scheme == 'wss' ? 'https' : 'http') +
              '://$host:$port/ws')); // form the correct url here

      request.headers.add('Connection', 'Upgrade');
      request.headers.add('Upgrade', 'websocket');
      request.headers.add(
          'Sec-WebSocket-Version', '13'); // insert the correct version here
      request.headers.add('Sec-WebSocket-Key', key.toLowerCase());

      //request.headers.add('Origin', 'http://localhost:5060');
      //request.headers.add('Sec-WebSocket-Protocol', 'sip');
      extHeaders.forEach((key, value) {
        request.headers.add(key, value);
      });

      var response = await request.close();
      var socket = await response.detachSocket();
      var webSocket = WebSocket.fromUpgradedSocket(
        socket,
        protocol: 'sip',
        serverSide: false,
      );

      return webSocket;
    } catch (e) {
      logger.error('error $e');
      throw e;
    }
  }
}
