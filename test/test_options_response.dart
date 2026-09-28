import 'dart:async';
import 'dart:io';

import 'package:sip_ua/sip_ua.dart';
import 'package:sip_ua/src/event_manager/event_manager.dart';
import 'package:sip_ua/src/event_manager/internal_events.dart';
import 'package:test/test.dart';

/// Local SIP OPTIONS peer. Copies the request's Via, From, To, Call-ID and
/// CSeq into a single 200, which is what the stack's sanity check accepts.
Future<HttpServer> _optionsServer() async {
  HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest req) {
    unawaited(() async {
      WebSocket socket = await WebSocketTransformer.upgrade(req);
      socket.listen((dynamic msg) {
        String text = msg.toString();
        if (!text.startsWith('OPTIONS ')) {
          return;
        }
        String? via = _header(text, 'via');
        String? from = _header(text, 'from');
        String? to = _header(text, 'to');
        String? callId = _header(text, 'call-id');
        String? cseq = _header(text, 'cseq');
        if (to != null && !to.contains('tag=')) {
          to = '$to;tag=opt200';
        }
        String response = 'SIP/2.0 200 OK\r\n'
            'Via: $via\r\n'
            'From: $from\r\n'
            'To: $to\r\n'
            'Call-ID: $callId\r\n'
            'CSeq: $cseq\r\n'
            'Content-Length: 0\r\n'
            '\r\n';
        socket.add(response);
      });
    }());
  });
  return server;
}

String? _header(String message, String name) {
  RegExpMatch? match =
      RegExp('^$name:\\s*(.*)\$', caseSensitive: false, multiLine: true)
          .firstMatch(message);
  return match?.group(1)?.trim();
}

void main() {
  test('outgoing OPTIONS delivers the response', () async {
    HttpServer server = await _optionsServer();
    SIPUAHelper helper = SIPUAHelper();
    Completer<void> connected = Completer<void>();
    Completer<EventSucceeded> succeeded = Completer<EventSucceeded>();
    addTearDown(() async {
      helper.stop();
      await server.close(force: true);
    });

    helper.addSipUaHelperListener(_TransportWait(connected));

    UaSettings settings = UaSettings();
    settings.transportType = TransportType.WS;
    settings.webSocketUrl = 'ws://127.0.0.1:${server.port}/sip';
    settings.uri = 'sip:alice@127.0.0.1';
    settings.register = false;
    await helper.start(settings);
    await connected.future.timeout(const Duration(seconds: 5));

    EventManager handlers = EventManager();
    handlers.on(EventSucceeded(), (EventSucceeded event) {
      if (!succeeded.isCompleted) {
        succeeded.complete(event);
      }
    });
    handlers.on(EventCallFailed(), (EventCallFailed event) {
      if (!succeeded.isCompleted) {
        succeeded.completeError(StateError('OPTIONS failed: ${event.cause}'));
      }
    });

    helper.sendOptions('sip:alice@127.0.0.1', 'ping', <String, dynamic>{
      'eventHandlers': handlers,
      'contentType': 'text/plain',
    });

    EventSucceeded event =
        await succeeded.future.timeout(const Duration(seconds: 2));
    expect(event.response, isNotNull);
  });
}

class _TransportWait implements SipUaHelperListener {
  _TransportWait(this.connected);

  final Completer<void> connected;

  @override
  void transportStateChanged(TransportState state) {
    if (state.state == TransportStateEnum.CONNECTED && !connected.isCompleted) {
      connected.complete();
    }
  }

  @override
  void registrationStateChanged(RegistrationState state) {}

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
