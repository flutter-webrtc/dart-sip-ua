import 'dart:async';
import 'dart:io';

import 'package:sip_ua/sip_ua.dart';
import 'package:sip_ua/src/transports/socket_interface.dart';
import 'package:sip_ua/src/transports/web_socket.dart';
import 'package:test/test.dart';

void main() {
  test('a late WebSocket open does not connect twice', () async {
    HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    int accepted = 0;
    server.listen((HttpRequest req) {
      accepted++;
      int which = accepted;
      unawaited(() async {
        // Hold the first handshake. The second must be able to upgrade
        // without waiting behind it, or the test cannot see the overlap.
        if (which == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
        WebSocket socket = await WebSocketTransformer.upgrade(req);
        socket.listen((dynamic _) {});
      }());
    });
    addTearDown(() => server.close(force: true));

    SIPUAWebSocket client =
        SIPUAWebSocket('ws://127.0.0.1:${server.port}/sip', messageDelay: 0);
    int connects = 0;
    client.onconnect = () {
      connects++;
    };
    client.ondata = (dynamic data) {};
    client.ondisconnect = (SIPUASocketInterface socket, bool error,
        int? closeCode, String? reason) {};

    client.connect();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    client.connect();
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    expect(connects, 1);
    client.disconnect();
  });

  test('connectTimeout reports a handshake the server never finishes',
      () async {
    HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    bool allow = false;
    server.listen((HttpRequest req) {
      if (!allow) {
        // Accepted, but never upgraded. WebSocket.connect waits here.
        return;
      }
      unawaited(() async {
        WebSocket socket = await WebSocketTransformer.upgrade(req);
        socket.listen((dynamic _) {});
      }());
    });
    addTearDown(() => server.close(force: true));

    WebSocketSettings settings = WebSocketSettings();
    settings.connectTimeout = const Duration(milliseconds: 300);
    SIPUAWebSocket client = SIPUAWebSocket('ws://127.0.0.1:${server.port}/sip',
        messageDelay: 0, webSocketSettings: settings);
    Completer<String> timedOut = Completer<String>();
    Completer<void> opened = Completer<void>();
    client.onconnect = () {
      if (!opened.isCompleted) {
        opened.complete();
      }
    };
    client.ondata = (dynamic data) {};
    client.ondisconnect = (SIPUASocketInterface socket, bool error,
        int? closeCode, String? reason) {
      if ((reason ?? '').contains('connect timeout') && !timedOut.isCompleted) {
        timedOut.complete(reason ?? '');
      }
    };

    client.connect();
    String reason = await timedOut.future.timeout(const Duration(seconds: 2));
    expect(reason, contains('connect timeout'));

    allow = true;
    client.connect();
    await opened.future.timeout(const Duration(seconds: 2));
    client.disconnect();
  });
}
