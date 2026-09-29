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
  DateTime? _connectedAt;

  /// The client carrying the handshake while it is in flight, so [close] can
  /// abort it.
  HttpClient? _handshakeClient;

  /// Set by [close]; a handshake that completes afterwards has no owner.
  bool _closed = false;

  void connect(
      {Iterable<String>? protocols,
      required WebSocketSettings webSocketSettings}) async {
    handleQueue();
    logger.i('connect $_url, ${webSocketSettings.extraHeaders}, $protocols');
    try {
      final WebSocket socket;
      if (webSocketSettings.allowBadCertificate) {
        /// Allow self-signed certificate, for test only.
        socket = await _connectForBadCertificate(_url, webSocketSettings);
      } else {
        socket = await _connectVerified(_url, protocols, webSocketSettings);
      }

      // close() ran while the handshake was in flight. Nothing owns this
      // socket now; left open, it kept pinging with no call on it (seen
      // connected 7 ms after a teardown and open for another 123 s).
      if (_closed) {
        logger.w('WebSocket $_url connected after close(), closing it');
        unawaited(socket.close());
        return;
      }
      _socket = socket;

      // Keep the connection warm. Periodic PING frames stop NAT/LB/proxy
      // idle-reaping of the flow between sparse SIP messages, which would
      // otherwise surface as an abnormal 1006 close mid-call. Applies to
      // both the normal and self-signed (fromUpgradedSocket) paths.
      final Duration? pingInterval = webSocketSettings.pingInterval;
      if (pingInterval != null) {
        _socket!.pingInterval = pingInterval;
        logger.d('WebSocket pingInterval set to ${pingInterval.inSeconds}s');
      }

      _connectedAt = DateTime.now();
      onOpen?.call();
      _socket!.listen((dynamic data) {
        onMessage?.call(data);
      }, onDone: () {
        final DateTime? connectedAt = _connectedAt;
        final String uptime = connectedAt == null
            ? 'unknown'
            : '${DateTime.now().difference(connectedAt).inSeconds}s';
        logger.w(
            'WebSocket closed [code:${_socket!.closeCode}, reason:${_socket!.closeReason}] '
            'after $uptime connected');
        onClose?.call(_socket!.closeCode, _socket!.closeReason);
      });
    } catch (e) {
      onClose?.call(500, e.toString());
    } finally {
      _handshakeClient = null;
    }
  }

  /// Connect with the server certificate verified against
  /// [WebSocketSettings.securityContext], or the platform default.
  Future<WebSocket> _connectVerified(String url, Iterable<String>? protocols,
      WebSocketSettings webSocketSettings) {
    final Object? context = webSocketSettings.securityContext;
    final HttpClient client =
        HttpClient(context: context is SecurityContext ? context : null);
    if (webSocketSettings.userAgent != null) {
      client.userAgent = webSocketSettings.userAgent;
    }
    _handshakeClient = client;
    return WebSocket.connect(url,
        protocols: protocols,
        headers: webSocketSettings.extraHeaders,
        customClient: client);
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
    _closed = true;
    // Abort a handshake still in flight; its socket would otherwise open
    // later with nobody left to close it.
    _handshakeClient?.close(force: true);
    if (_socket != null) _socket!.close();
  }

  bool isConnecting() {
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
      _handshakeClient = client;

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
