import 'dart:html';
import 'dart:js_util' as JSUtils;
import 'package:sip_ua/src/sip_ua_helper.dart';

import '../logger.dart';

typedef void OnMessageCallback(dynamic msg);
typedef void OnCloseCallback(int code, String reason);
typedef void OnOpenCallback();

class WebSocketImpl {
  String _url;
  WebSocket _socket;
  OnOpenCallback onOpen;
  OnMessageCallback onMessage;
  OnCloseCallback onClose;
  final logger = Log();

  WebSocketImpl(this._url);

  void connect(
      {Iterable<String> protocols, WebSocketSettings webSocketSettings}) async {
    logger.info('connect $_url, ${webSocketSettings.extraHeaders}, $protocols');
    try {
      _socket = WebSocket(_url, 'sip');
      _socket.onOpen.listen((e) {
        this?.onOpen();
      });

      _socket.onMessage.listen((e) async {
        if (e.data is Blob) {
          dynamic arrayBuffer = await JSUtils.promiseToFuture(
              JSUtils.callMethod(e.data, 'arrayBuffer', []));
          String message = String.fromCharCodes(arrayBuffer.asUint8List());
          this?.onMessage(message);
        } else {
          this?.onMessage(e.data);
        }
      });

      _socket.onClose.listen((e) {
        this?.onClose(e.code, e.reason);
      });
    } catch (e) {
      this?.onClose(e.code, e.reason);
    }
  }

  void send(data) {
    if (_socket != null && _socket.readyState == WebSocket.OPEN) {
      _socket.send(data);
      logger.debug('send: \n\n$data');
    } else {
      logger.error('WebSocket not connected, message $data not sent');
    }
  }

  bool isConnecting() {
    return _socket != null && _socket.readyState == WebSocket.CONNECTING;
  }

  void close() {
    _socket.close();
  }
}
