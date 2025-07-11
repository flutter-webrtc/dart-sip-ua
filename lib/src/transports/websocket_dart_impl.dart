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
  void connect(
      {Iterable<String>? protocols,
      required WebSocketSettings webSocketSettings}) async {
    handleQueue();
    logger.i('connect $_url, ${webSocketSettings.extraHeaders}, $protocols');
    try {
      if (webSocketSettings.allowBadCertificate ||
          webSocketSettings.debugCertificate) {
        // Depending on the settings, it will allow self-signed certificates or debug them.
        _socket =
            await _connectWithBadCertificateHandling(_url, webSocketSettings);
      } else {
        _socket = await WebSocket.connect(_url,
            protocols: protocols, headers: webSocketSettings.extraHeaders);
      }

      onOpen?.call();
      _socket!.listen((dynamic data) {
        onMessage?.call(data);
      }, onDone: () {
        onClose?.call(_socket!.closeCode, _socket!.closeReason);
      });
    } catch (e) {
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
    if (_socket != null) _socket!.close();
  }

  bool isConnecting() {
    return _socket != null && _socket!.readyState == WebSocket.connecting;
  }

  Future<WebSocket> _connectWithBadCertificateHandling(
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
        if (webSocketSettings.allowBadCertificate) {
          logger.w('Allow self-signed certificate => $host:$port. ');
          return true;
        } else if (webSocketSettings.debugCertificate) {
          logger.w(
              'Server returns a server certificate that cannot be authenticated => $host:$port. ');
          String certInfo = '\n';
          certInfo += ' Certificate subject: ${cert.subject}\n';
          certInfo += ' Certificate issuer: ${cert.issuer}\n';
          certInfo += ' Certificate valid from: ${cert.startValidity}\n';
          certInfo += ' Certificate valid to: ${cert.endValidity}\n';
          certInfo += ' Certificate SHA-1 fingerprint: ${cert.sha1}\n';

          logger.w('Certificate details: {$certInfo}');
          return false;
        } else {
          return false; // reject the certificate
        }
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
