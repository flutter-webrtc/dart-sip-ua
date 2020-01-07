/*
 * Theses classes simply serve to remove compile errors
 * when building for a flutter environment 
 */

class WebSocket {
  static var OPEN;
  static var CONNECTING;

  WebSocket(String url, String s);

  get onOpen => null;

  get onMessage => null;

  get onClose => null;

  get readyState => null;

  void send(data) {}

  void close() {}
}

class Blob {}

dynamic callMethod(var a, var b, var c) {}

Future<dynamic> promiseToFuture(var promise) {}
