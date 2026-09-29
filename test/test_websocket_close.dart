import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'package:sip_ua/src/sip_ua_helper.dart';
import 'package:sip_ua/src/transports/websocket_dart_impl.dart';

/// A local WebSocket server that holds each upgrade for [upgradeDelay], and
/// records every socket it accepts.
class _SlowServer {
  _SlowServer(this.upgradeDelay);

  final Duration upgradeDelay;
  late final HttpServer _server;
  final List<WebSocket> accepted = <WebSocket>[];

  /// Completes when the matching [accepted] socket's stream ends, i.e. when
  /// the client side is gone.
  final List<Future<void>> ended = <Future<void>>[];

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((HttpRequest request) async {
      await Future<void>.delayed(upgradeDelay);
      try {
        final WebSocket ws = await WebSocketTransformer.upgrade(request,
            protocolSelector: (List<String> protocols) => 'sip');
        accepted.add(ws);
        final Completer<void> gone = Completer<void>();
        ended.add(gone.future);
        // Only a listened-to socket notices the peer going away.
        ws.listen((dynamic _) {},
            onError: (Object _) {},
            onDone: () => gone.isCompleted ? null : gone.complete());
      } catch (_) {
        // The client gave up before the upgrade: nothing was opened.
      }
    });
    return 'ws://127.0.0.1:${_server.port}';
  }

  Future<void> stop() async {
    for (final WebSocket ws in accepted) {
      await ws.close();
    }
    await _server.close(force: true);
  }
}

List<void Function()> testFunctions = <void Function()>[
  () => test('a socket opens and reports it', () async {
        final _SlowServer server = _SlowServer(Duration.zero);
        final String url = await server.start();
        final SIPUAWebSocketImpl ws = SIPUAWebSocketImpl(url, 0);
        final Completer<void> opened = Completer<void>();
        ws.onOpen = opened.complete;

        ws.connect(
            protocols: <String>['sip'],
            webSocketSettings: WebSocketSettings());
        await opened.future.timeout(const Duration(seconds: 5));

        ws.close();
        await server.stop();
      }),
  () => test('close() during the handshake leaves no socket open', () async {
        final _SlowServer server =
            _SlowServer(const Duration(milliseconds: 300));
        final String url = await server.start();
        final SIPUAWebSocketImpl ws = SIPUAWebSocketImpl(url, 0);
        bool opened = false;
        ws.onOpen = () => opened = true;

        ws.connect(
            protocols: <String>['sip'],
            webSocketSettings: WebSocketSettings());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        ws.close();
        await Future<void>.delayed(const Duration(milliseconds: 700));

        expect(opened, isFalse);
        // Whatever the server may have accepted must not stay open.
        for (final Future<void> gone in server.ended) {
          await gone.timeout(const Duration(seconds: 2));
        }
        await server.stop();
      }),
];

void main() {
  for (void Function() func in testFunctions) {
    func();
  }
}
