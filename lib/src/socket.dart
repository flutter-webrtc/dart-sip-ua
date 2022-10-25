import 'grammar.dart';
import 'logger.dart';
import 'transports/websocket_interface.dart';
import 'utils.dart' as Utils;

/// Socket Interface.
abstract class Socket {
  late String via_transport;
  String? get url;
  String? get sip_uri;

  void connect();
  void disconnect();
  void send(dynamic data);

  void Function()? onconnect;
  void Function(WebSocketInterface socket, bool error, int? closeCode,
      String? reason)? ondisconnect;
  void Function(dynamic data)? ondata;
}

bool isSocket(dynamic socket) {
  // Ignore if an array is given.
  if (socket is List) {
    return false;
  }

  if (socket == null) {
    logger.e('null DartSIP.Socket instance');
    return false;
  }

  // Check Properties.
  try {
    if (!Utils.isString(socket.url)) {
      logger.e('missing or invalid DartSIP.Socket url property');
      throw Error();
    }

    if (!Utils.isString(socket.via_transport)) {
      logger.e('missing or invalid DartSIP.Socket via_transport property');
      throw Error();
    }

    if (Grammar.parse(socket.sip_uri, 'SIP_URI') == -1) {
      logger.e('missing or invalid DartSIP.Socket sip_uri property');
      throw Error();
    }
  } catch (e) {
    return false;
  }

  if (socket is! Socket) {
    return false;
  }

  // Check Methods.
  if (socket.connect == null)
    return false;
  else if (socket.disconnect == null)
    return false;
  else if (socket.send == null) {
    return false;
  }

  return true;
}
