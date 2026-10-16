import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'package:sip_ua/sip_ua.dart';

/// Accepts the socket and records REGISTER, but never answers it, so the
/// client transaction is still alive when start() is called again.
Future<HttpServer> _hangingRegistrar(Completer<void> sawRegister) async {
  HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest req) {
    unawaited(() async {
      WebSocket socket = await WebSocketTransformer.upgrade(req);
      socket.listen((dynamic msg) {
        if (msg.toString().startsWith('REGISTER ') &&
            !sawRegister.isCompleted) {
          sawRegister.complete();
        }
      });
    }());
  });
  return server;
}

void main() {
  test('replaced UA does not emit transport or registration events', () async {
    Completer<void> sawRegister = Completer<void>();
    HttpServer server = await _hangingRegistrar(sawRegister);
    SIPUAHelper helper = SIPUAHelper();
    _Recorder recorder = _Recorder();
    helper.addSipUaHelperListener(recorder);
    addTearDown(() async {
      helper.stop();
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      await server.close(force: true);
    });

    UaSettings settings = UaSettings();
    settings.transportType = TransportType.WS;
    settings.webSocketUrl = 'ws://127.0.0.1:${server.port}/sip';
    settings.uri = 'sip:alice@127.0.0.1';
    settings.authorizationUser = 'alice';
    settings.password = 'secret';
    settings.register = true;

    await helper.start(settings);
    await recorder.connected.future.timeout(const Duration(seconds: 5));
    await sawRegister.future.timeout(const Duration(seconds: 5));

    recorder.clear();
    await helper.start(settings);
    await recorder.connected.future.timeout(const Duration(seconds: 5));
    // stop() waits 2s before disconnecting a UA that still has a transaction.
    // Timer F is 32s, so a failure inside this window is that deferred close.
    await Future<void>.delayed(const Duration(milliseconds: 2500));

    expect(
        recorder.transports.where((TransportState state) =>
            state.state == TransportStateEnum.DISCONNECTED &&
            state.cause?.reason_phrase == 'close by local'),
        isEmpty);
    expect(
        recorder.registrations.where((RegistrationState state) =>
            state.state == RegistrationStateEnum.REGISTRATION_FAILED),
        isEmpty);
  });
}

class _Recorder implements SipUaHelperListener {
  Completer<void> connected = Completer<void>();
  final List<TransportState> transports = <TransportState>[];
  final List<RegistrationState> registrations = <RegistrationState>[];

  void clear() {
    transports.clear();
    registrations.clear();
    connected = Completer<void>();
  }

  @override
  void transportStateChanged(TransportState state) {
    transports.add(state);
    if (state.state == TransportStateEnum.CONNECTED && !connected.isCompleted) {
      connected.complete();
    }
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    registrations.add(state);
  }

  @override
  void callStateChanged(Call call, CallState state) {}

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void onNewReinvite(ReInvite event) {}

  @override
  void onNewInfo(SipInfo info) {}
}
