import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package:sip_ua/sip_ua.dart';
import 'package:sip_ua/src/transports/socket_interface.dart';
import 'package:sip_ua/src/transports/web_socket.dart';

/// Completes the WebSocket handshake by hand and then goes silent: it never
/// answers a ping, like a peer behind a NAT binding that has expired.
Future<HttpServer> _silentPeer() async {
  HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest req) {
    unawaited(() async {
      String key = req.headers.value('sec-websocket-key')!;
      String accept = base64.encode(sha1
          .convert(utf8.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11'))
          .bytes);
      Socket socket = await req.response.detachSocket(writeHeaders: false);
      socket.write('HTTP/1.1 101 Switching Protocols\r\n'
          'Upgrade: websocket\r\n'
          'Connection: Upgrade\r\n'
          'Sec-WebSocket-Accept: $accept\r\n'
          'Sec-WebSocket-Protocol: sip\r\n'
          '\r\n');
      socket.listen((List<int> _) {}, onError: (Object _) {});
    }());
  });
  return server;
}

/// Connects to a silent peer and reports whether the socket was closed
/// within [within].
Future<bool> _closedWithin(Duration? pingInterval, Duration within) async {
  HttpServer server = await _silentPeer();
  addTearDown(() => server.close(force: true));

  WebSocketSettings settings = WebSocketSettings();
  settings.pingInterval = pingInterval;
  SIPUAWebSocket client = SIPUAWebSocket('ws://127.0.0.1:${server.port}/sip',
      messageDelay: 0, webSocketSettings: settings);
  Completer<void> opened = Completer<void>();
  Completer<void> closed = Completer<void>();
  client.onconnect = () => opened.complete();
  client.ondata = (dynamic data) {};
  client.ondisconnect = (SIPUASocketInterface socket, bool error,
      int? closeCode, String? reason) {
    if (!closed.isCompleted) {
      closed.complete();
    }
  };

  client.connect();
  await opened.future.timeout(const Duration(seconds: 2));
  bool result = await closed.future
      .then((_) => true)
      .timeout(within, onTimeout: () => false);
  client.disconnect();
  return result;
}

List<void Function()> testFunctions = <void Function()>[
  () => test('pingInterval closes a socket whose peer stopped answering',
          () async {
        expect(
            await _closedWithin(
                const Duration(milliseconds: 200), const Duration(seconds: 2)),
            isTrue);
      }),
  () => test('without pingInterval the socket is left as it was', () async {
        expect(await _closedWithin(null, const Duration(seconds: 1)), isFalse);
      }),
];

void main() {
  for (Function func in testFunctions) {
    func();
  }
}
