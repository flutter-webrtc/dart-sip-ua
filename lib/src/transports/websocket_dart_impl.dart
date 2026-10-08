import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sip_ua/src/sip_ua_helper.dart';
import '../logger.dart';

typedef OnMessageCallback = void Function(dynamic msg);
typedef OnCloseCallback = void Function(int? code, String? reason);
typedef OnOpenCallback = void Function();

class SIPUAWebSocketImpl {
  SIPUAWebSocketImpl(this._url, this.messageDelay);

  final String _url;
  WebSocket? _socket;
  OnOpenCallback? onOpen;
  OnMessageCallback? onMessage;
  OnCloseCallback? onClose;
  final int messageDelay;

  /// Identifies the handshake currently in flight. close() and a connect
  /// timeout bump it so a socket that completes afterwards is discarded.
  int _attempt = 0;
  bool _connecting = false;

  /// True only when [WebSocketSettings.connectTimeout] is set. Without a
  /// deadline, [isConnecting] stays false during the await and a second
  /// connect() may overlap this one — that overlap is what recovers a
  /// handshake the OS never finishes.
  bool _blockOverlap = false;
  Timer? _connectTimer;

  void connect(
      {Iterable<String>? protocols,
      required WebSocketSettings webSocketSettings}) async {
    handleQueue();
    logger.i('connect $_url, ${webSocketSettings.extraHeaders}, $protocols');
    int attempt = ++_attempt;
    _connecting = true;
    _blockOverlap = webSocketSettings.connectTimeout != null;
    _connectTimer?.cancel();
    Duration? timeout = webSocketSettings.connectTimeout;
    if (timeout != null) {
      _connectTimer = Timer(timeout, () {
        if (attempt != _attempt) {
          return;
        }
        _connecting = false;
        _connectTimer = null;
        _attempt++;
        onClose?.call(1006, 'connect timeout');
      });
    }
    try {
      WebSocket socket;
      if (webSocketSettings.allowBadCertificate) {
        /// Allow self-signed certificate, for test only.
        socket = await _connectForBadCertificate(_url, webSocketSettings);
      } else {
        socket = await WebSocket.connect(_url,
            protocols: protocols, headers: webSocketSettings.extraHeaders);
      }

      if (attempt != _attempt) {
        socket.close();
        return;
      }

      _connectTimer?.cancel();
      _connectTimer = null;
      _connecting = false;
      _socket = socket;

      // Applies to both branches above. Null keeps dart:io's default of not
      // pinging at all, so this is a no-op unless a caller opts in.
      _socket!.pingInterval = webSocketSettings.pingInterval;

      onOpen?.call();
      _socket!.listen((dynamic data) {
        if (attempt != _attempt) {
          return;
        }
        onMessage?.call(data);
      }, onDone: () {
        if (attempt != _attempt) {
          return;
        }
        onClose?.call(_socket?.closeCode, _socket?.closeReason);
      });
    } catch (e) {
      if (attempt != _attempt) {
        return;
      }
      _connecting = false;
      _connectTimer?.cancel();
      _connectTimer = null;
      onClose?.call(500, e.toString());
    }
  }

  final StreamController<dynamic> queue = StreamController<dynamic>.broadcast();
  void handleQueue() async {
    queue.stream.asyncMap((dynamic event) async {
      await Future<void>.delayed(Duration(milliseconds: messageDelay));
      return event;
    }).listen((dynamic event) async {
      _socket!.add(event);
      logger.d('send: \n\n$event');
    });
  }

  void send(dynamic data) async {
    if (_socket != null) {
      queue.add(data);
    }
  }

  void close() {
    _attempt++;
    _connecting = false;
    _blockOverlap = false;
    _connectTimer?.cancel();
    _connectTimer = null;
    WebSocket? socket = _socket;
    _socket = null;
    if (socket != null) {
      socket.close();
    }
  }

  bool isConnecting() {
    if (_blockOverlap && _connecting) {
      return true;
    }
    return _socket != null && _socket!.readyState == WebSocket.connecting;
  }

  /// For test only.
  Future<WebSocket> _connectForBadCertificate(
      String url, WebSocketSettings webSocketSettings) async {
    try {
      Random r = Random();
      String key = base64.encode(List<int>.generate(16, (_) => r.nextInt(255)));
      SecurityContext securityContext = SecurityContext();
      HttpClient client = HttpClient(context: securityContext);

      if (webSocketSettings.userAgent != null) {
        client.userAgent = webSocketSettings.userAgent;
      }

      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        logger.w('Allow self-signed certificate => $host:$port. ');
        return true;
      };

      Uri parsed_uri = Uri.parse(url);
      Uri uri = parsed_uri.replace(
          scheme: parsed_uri.scheme == 'wss' ? 'https' : 'http');

      HttpClientRequest request =
          await client.getUrl(uri); // form the correct url here
      request.headers.add('Connection', 'Upgrade', preserveHeaderCase: true);
      request.headers.add('Upgrade', 'websocket', preserveHeaderCase: true);
      request.headers.add('Sec-WebSocket-Version', '13',
          preserveHeaderCase: true); // insert the correct version here
      request.headers.add('Sec-WebSocket-Key', key.toLowerCase(),
          preserveHeaderCase: true);
      request.headers
          .add('Sec-WebSocket-Protocol', 'sip', preserveHeaderCase: true);

      webSocketSettings.extraHeaders.forEach((String key, dynamic value) {
        request.headers.add(key, value, preserveHeaderCase: true);
      });

      HttpClientResponse response = await request.close();
      Socket socket = await response.detachSocket();
      WebSocket webSocket = WebSocket.fromUpgradedSocket(
        socket,
        protocol: 'sip',
        serverSide: false,
      );

      return webSocket;
    } catch (e) {
      logger.e('error $e');
      rethrow;
    }
  }
}
