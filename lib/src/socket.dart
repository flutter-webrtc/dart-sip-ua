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
