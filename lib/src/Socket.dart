import 'Utils.dart' as Utils;
import 'Grammar.dart';
import 'logger.dart';

final logger = Logger('Socket');
debug(msg) => logger.debug(msg);
debugerror(error) => logger.error(error);

/// Socket Interface.
abstract class Socket {

  get via_transport;
  get url;
  get sip_uri;

  connect();
  disconnect();
  send(data);

  dynamic onconnect;
  dynamic ondisconnect;
  dynamic ondata;
}

isSocket(socket) {
  // Ignore if an array is given.
  if (socket is List) {
    return false;
  }

  if (socket == null) {
    debugerror('null JsSIP.Socket instance');

    return false;
  }

  // Check Properties.
  try {
    if (!Utils.isString(socket.url)) {
      debugerror('missing or invalid JsSIP.Socket url property');
      throw new Error();
    }

    if (!Utils.isString(socket.via_transport)) {
      debugerror('missing or invalid JsSIP.Socket via_transport property');
      throw new Error();
    }

    if (Grammar.parse(socket.sip_uri, 'SIP_URI') == -1) {
      debugerror('missing or invalid JsSIP.Socket sip_uri property');
      throw new Error();
    }
  } catch (e) {
    return false;
  }

  if(socket is! Socket)
    return false;

  // Check Methods.
  if (socket.connect == null || socket.connect is! Function)
    return false;
  else if (socket.disconnect == null || socket.disconnect is! Function)
    return false;
  else if (socket.send == null || socket.send is! Function) return false;

  return true;
}
