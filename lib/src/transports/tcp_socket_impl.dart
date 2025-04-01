import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../logger.dart';
import '../sip_ua_helper.dart';

typedef OnMessageCallback = void Function(dynamic msg);
typedef OnCloseCallback = void Function(int? code, String? reason);
typedef OnOpenCallback = void Function();

class SIPUATcpSocketImpl {
  SIPUATcpSocketImpl(this.messageDelay, this._host, this._port);

  final String _host;
  final String _port;

  Socket? _socket;
  OnOpenCallback? onOpen;
  OnMessageCallback? onData;
  OnCloseCallback? onClose;
  final int messageDelay;

  void connect(
      {Iterable<String>? protocols,
      required TcpSocketSettings tcpSocketSettings}) async {
    handleQueue();
    logger.i('connect $_host:$_port');
    try {
      if (tcpSocketSettings.allowBadCertificate) {
        // /// Allow self-signed certificate, for test only.
        // _socket = await _connectForBadCertificate(_url, tcpSocketSettings);
      } else {
        // used to have these
        //protocols: protocols, headers: webSocketSettings.extraHeaders
        _socket = await Socket.connect(
          _host,
          int.parse(_port),
        );
      }

      onOpen?.call();

      _socket!.listen((dynamic data) {
        onData?.call(data);
      }, onDone: () {
        //  onClose?.call(_socket!., _socket!.closeReason);
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
      _socket!.add(event.codeUnits);
      logger.d('send: \n\n$event');
    });
  }

  void send(dynamic data) async {
    if (_socket != null) {
      queue.add(data);
    }
  }

  void close() {
    _socket!.close();
  }
}
