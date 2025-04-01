import 'dart:html';
import 'dart:js_util' as JSUtils;

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
    logger.i('connect $_url, ${webSocketSettings.extraHeaders}, $protocols');
    try {
      _socket = WebSocket(_url, 'sip');
      _socket!.onOpen.listen((Event e) {
        onOpen?.call();
      });

      _socket!.onMessage.listen((MessageEvent e) async {
        if (e.data is Blob) {
          dynamic arrayBuffer = await JSUtils.promiseToFuture(
              JSUtils.callMethod(e.data, 'arrayBuffer', <Object>[]));
          String message = String.fromCharCodes(arrayBuffer.asUint8List());
          onMessage?.call(message);
        } else {
          onMessage?.call(e.data);
        }
      });

      _socket!.onClose.listen((CloseEvent e) {
        onClose?.call(e.code, e.reason);
      });
    } catch (e) {
      onClose?.call(0, e.toString());
    }
  }

  void send(dynamic data) {
    if (_socket != null && _socket!.readyState == WebSocket.OPEN) {
      _socket!.send(data);
      logger.d('send: \n\n$data');
    } else {
      logger.e('WebSocket not connected, message $data not sent');
    }
  }

  bool isConnecting() {
    return _socket != null && _socket!.readyState == WebSocket.CONNECTING;
  }

  void close() {
    _socket!.close();
  }
}
