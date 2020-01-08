import 'grammar.dart';
import 'utils.dart' as Utils;
import 'transports/websocket_interface.dart';
import 'logger.dart';

final logger = Log();

/// Socket Interface.
abstract class Socket {
  get via_transport;
  get url;
  get sip_uri;

  connect();
  disconnect();
  send(data);

  void Function() onconnect;
  void Function(
          WebSocketInterface socket, bool error, int closeCode, String reason)
      ondisconnect;
  void Function(dynamic data) ondata;
}

isSocket(socket) {
  // Ignore if an array is given.
  if (socket is List) {
    return false;
  }

  if (socket == null) {
    logger.error('null DartSIP.Socket instance');
    return false;
  }

  // Check Properties.
  try {
    if (!Utils.isString(socket.url)) {
      logger.error('missing or invalid DartSIP.Socket url property');
      throw new Error();
    }

    if (!Utils.isString(socket.via_transport)) {
      logger.error('missing or invalid DartSIP.Socket via_transport property');
      throw new Error();
    }

    if (Grammar.parse(socket.sip_uri, 'SIP_URI') == -1) {
      logger.error('missing or invalid DartSIP.Socket sip_uri property');
      throw new Error();
    }
  } catch (e) {
    return false;
  }

  if (socket is! Socket) return false;

  // Check Methods.
  if (socket.connect == null || socket.connect is! Function)
    return false;
  else if (socket.disconnect == null || socket.disconnect is! Function)
    return false;
  else if (socket.send == null || socket.send is! Function) return false;

  return true;
}
