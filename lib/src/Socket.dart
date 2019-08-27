import 'Utils.dart' as Utils;
import 'Grammar.dart';
import 'logger.dart';

final logger = Logger('Socket');
debug(msg) => logger.debug(msg);
debugerror(error) => logger.error(error);

/**
 * Interface documentation: https://jssip.net/documentation/$last_version/api/socket/
 *
 * interface Socket {
 *  attribute String via_transport
 *  attribute String url
 *  attribute String sip_uri
 *
 *  method connect();
 *  method disconnect();
 *  method send(data);
 *
 *  attribute EventHandler onconnect
 *  attribute EventHandler ondisconnect
 *  attribute EventHandler ondata
 * }
 *
 */

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

  // Check Methods.
  if (socket.connect == null || socket.connect is! Function)
    return false;
  else if (socket.disconnect == null|| socket.disconnect is! Function)
    return false;
  else if (socket.send == null || socket.send is! Function) return false;

  return true;
}
