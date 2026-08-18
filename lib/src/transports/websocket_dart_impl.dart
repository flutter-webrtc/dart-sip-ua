import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sip_ua/src/sip_ua_helper.dart';
import '../logger.dart';

typedef OnMessageCallback = void Function(dynamic msg);
typedef OnCloseCallback = void Function(int? code, String? reason);
typedef OnOpenCallback = void Function();

/// Close code reported when the socket dies without a close handshake,
/// i.e. RFC 6455 `1006 abnormal closure`.
const int abnormalClosure = 1006;

class SIPUAWebSocketImpl {
  SIPUAWebSocketImpl(this._url, this.messageDelay);

  final String _url;
  WebSocket? _socket;
  OnOpenCallback? onOpen;
  OnMessageCallback? onMessage;
  OnCloseCallback? onClose;
  final int messageDelay;

  /// Set once the death of the socket has been reported upstream, or once the
  /// caller closed it on purpose. A socket dying on error usually emits both
  /// an error and a done event, and each report would arm its own
  /// reconnection.
  bool _closeHandled = false;

  void connect(
      {Iterable<String>? protocols,
      required WebSocketSettings webSocketSettings}) async {
    handleQueue();
    logger.i('connect $_url, ${webSocketSettings.extraHeaders}, $protocols');
    try {
      if (webSocketSettings.allowBadCertificate) {
        /// Allow self-signed certificate, for test only.
        _socket = await _connectForBadCertificate(_url, webSocketSettings);
      } else {
        _socket = await WebSocket.connect(_url,
            protocols: protocols, headers: webSocketSettings.extraHeaders);
      }

      // Keep alive: `dart:io` emits the ping frames and closes the connection
      // when no pong comes back, which is the only way to notice a half open
      // socket (TCP dead on the network but never closed on our side).
      _socket!.pingInterval = webSocketSettings.pingInterval;

      // Listen before signalling the open state: a message arriving in
      // between would be lost.
      _socket!.listen((dynamic data) {
        onMessage?.call(data);
      }, onError: (Object error, StackTrace stackTrace) {
        logger.e('WebSocket $_url error: $error',
            error: error, stackTrace: stackTrace);
        _handleClose(_socket?.closeCode ?? abnormalClosure,
            _socket?.closeReason ?? error.toString());
      }, onDone: () {
        _handleClose(_socket?.closeCode, _socket?.closeReason);
      });

      onOpen?.call();
    } catch (e) {
      _handleClose(500, e.toString());
    }
  }

  final StreamController<dynamic> queue = StreamController<dynamic>.broadcast();
  StreamSubscription<dynamic>? _queueSubscription;
  void handleQueue() async {
    _queueSubscription = queue.stream.asyncMap((dynamic event) async {
      await Future<void>.delayed(Duration(milliseconds: messageDelay));
      return event;
    }).listen((dynamic event) {
      // This is where the write really happens, `send()` only enqueues. A
      // failure here must surface as a disconnection, otherwise the message
      // vanishes while the transport keeps believing it is connected.
      try {
        _socket!.add(event);
        logger.d('send: \n\n$event');
      } catch (error, stackTrace) {
        logger.e('WebSocket $_url send failure: $error',
            error: error, stackTrace: stackTrace);
        _handleClose(
            _socket?.closeCode ?? abnormalClosure, 'send failure: $error');
      }
    }, onError: (Object error, StackTrace stackTrace) {
      logger.e('WebSocket $_url send queue failure: $error',
          error: error, stackTrace: stackTrace);
      _handleClose(
          _socket?.closeCode ?? abnormalClosure, 'send queue failure: $error');
    });
  }

  void send(dynamic data) async {
    if (_socket == null || queue.isClosed) {
      logger.e('WebSocket $_url not connected, message not sent');
      return;
    }
    queue.add(data);
  }

  void close() {
    // Closing on purpose: the caller already knows, nothing to report back.
    _closeHandled = true;
    _closeQueue();
    if (_socket != null) _socket!.close();
  }

  bool isConnecting() {
    return _socket != null && _socket!.readyState == WebSocket.connecting;
  }

  /// Reports the death of the socket upstream, at most once.
  void _handleClose(int? code, String? reason) {
    if (_closeHandled) return;
    _closeHandled = true;
    _closeQueue();
    onClose?.call(code, reason);
  }

  /// Releases the send queue: the socket is gone, nothing can be written any
  /// more, and a brand new instance is built on every reconnection.
  void _closeQueue() {
    _queueSubscription?.cancel();
    _queueSubscription = null;
    if (!queue.isClosed) queue.close();
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
