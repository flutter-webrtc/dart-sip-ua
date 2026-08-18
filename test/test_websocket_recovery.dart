import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'package:sip_ua/src/sip_ua_helper.dart';
import 'package:sip_ua/src/transports/socket_interface.dart';
import 'package:sip_ua/src/transports/web_socket.dart';

/// Regression tests for the recovery path of [SIPUAWebSocket]: a socket that
/// dies must always be reported through `ondisconnect`, otherwise the
/// transport keeps believing it is connected and never reconnects.
///
/// Both scenarios go through a raw TCP proxy sitting between the client and a
/// local WebSocket server, the only way to reproduce a connection dying
/// without a close handshake and a half open connection.
///
/// The first one is a non regression guard, it already held before the ping
/// keep alive. The second one only passes with it: without a ping, nothing is
/// ever emitted and the socket stays believed connected forever.
List<void Function()> testFunctions = <void Function()>[
  () => test(' WebSocket: abrupt disconnection is reported', () async {
        _EchoServer server = await _EchoServer.start();
        _TcpProxy proxy = await _TcpProxy.start(server.port);
        Completer<String?> disconnected = Completer<String?>();

        SIPUAWebSocket client =
            SIPUAWebSocket('ws://127.0.0.1:${proxy.port}/sip', messageDelay: 0);

        client.onconnect = () {
          // The connection dies without a close frame: cable unplugged, RST
          // from a proxy, Wi-Fi to mobile handover.
          proxy.killConnections();
          // Exercise the write path on the dead socket: it must not throw out
          // of the queue listener nor keep the transport hanging.
          client.send('OPTIONS sip:127.0.0.1 SIP/2.0\r\n\r\n');
        };
        client.ondata = (dynamic data) {};
        client.ondisconnect = (SIPUASocketInterface socket, bool error,
            int? closeCode, String? reason) {
          if (!disconnected.isCompleted) disconnected.complete(reason);
        };
        client.connect();

        String? reason = await disconnected.future.timeout(
            const Duration(seconds: 10),
            onTimeout: () =>
                throw StateError('the death of the socket was never reported'));
        print('disconnected => $reason');
        expect(client.isConnected(), false);

        client.disconnect();
        await proxy.stop();
        await server.stop();
      }),
  () => test(' WebSocket: half open socket is detected by the ping', () async {
        _EchoServer server = await _EchoServer.start();
        _TcpProxy proxy = await _TcpProxy.start(server.port);
        Completer<String?> disconnected = Completer<String?>();

        WebSocketSettings settings = WebSocketSettings();
        settings.pingInterval = const Duration(seconds: 2);

        SIPUAWebSocket client = SIPUAWebSocket(
            'ws://127.0.0.1:${proxy.port}/sip',
            messageDelay: 0,
            webSocketSettings: settings);

        client.onconnect = () {
          // Nothing travels any more, but the socket stays open on both
          // sides: without the ping nobody can ever notice.
          proxy.blackHole = true;
        };
        client.ondata = (dynamic data) {};
        client.ondisconnect = (SIPUASocketInterface socket, bool error,
            int? closeCode, String? reason) {
          if (!disconnected.isCompleted) disconnected.complete(reason);
        };
        client.connect();

        String? reason = await disconnected.future.timeout(
            const Duration(seconds: 15),
            onTimeout: () =>
                throw StateError('the half open socket was never detected'));
        print('disconnected => $reason');
        expect(client.isConnected(), false);

        client.disconnect();
        await proxy.stop();
        await server.stop();
      }),
];

/// Minimal WebSocket server echoing back whatever it receives.
class _EchoServer {
  _EchoServer(this._server);

  static Future<_EchoServer> start() async {
    HttpServer server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((HttpRequest req) async {
      if (req.uri.path != '/sip') {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      WebSocket socket = await WebSocketTransformer.upgrade(req);
      socket.listen((dynamic msg) => socket.add(msg), onError: (dynamic e) {});
    });
    return _EchoServer(server);
  }

  final HttpServer _server;

  int get port => _server.port;

  Future<void> stop() => _server.close(force: true);
}

/// Raw TCP proxy able to kill the connections it relays, or to stop relaying
/// while keeping them open.
class _TcpProxy {
  _TcpProxy(this._server, this._targetPort);

  static Future<_TcpProxy> start(int targetPort) async {
    ServerSocket server = await ServerSocket.bind('127.0.0.1', 0);
    _TcpProxy proxy = _TcpProxy(server, targetPort);
    server.listen(proxy._relay);
    return proxy;
  }

  final ServerSocket _server;
  final int _targetPort;
  final List<Socket> _sockets = <Socket>[];

  /// Stops relaying in both directions without closing anything: the
  /// connection looks alive to both ends while nothing goes through.
  bool blackHole = false;

  int get port => _server.port;

  Future<void> _relay(Socket downstream) async {
    Socket upstream = await Socket.connect('127.0.0.1', _targetPort);
    _sockets.addAll(<Socket>[downstream, upstream]);
    downstream.listen((List<int> data) {
      if (!blackHole) upstream.add(data);
    }, onError: (dynamic e) {}, onDone: () => upstream.destroy());
    upstream.listen((List<int> data) {
      if (!blackHole) downstream.add(data);
    }, onError: (dynamic e) {}, onDone: () => downstream.destroy());
  }

  void killConnections() {
    for (Socket socket in _sockets) {
      socket.destroy();
    }
    _sockets.clear();
  }

  Future<void> stop() async {
    killConnections();
    await _server.close();
  }
}

void main() {
  for (Function func in testFunctions) {
    func();
  }
}
