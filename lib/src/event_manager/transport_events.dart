import 'package:sip_ua/src/transports/socket_interface.dart';
import '../transports/web_socket.dart';
import 'events.dart';

class EventSocketConnected extends EventType {
  EventSocketConnected({this.socket});
  SocketInterface? socket;
}

class EventSocketConnecting extends EventType {
  EventSocketConnecting({this.socket});
  SocketInterface? socket;
}

class EventSocketDisconnected extends EventType {
  EventSocketDisconnected({SocketInterface? socket, this.cause});
  SocketInterface? socket;
  ErrorCause? cause;
}
