import '../transports/socket_interface.dart';
import '../transports/web_socket.dart';
import 'events.dart';

class EventSocketConnected extends EventType {
  EventSocketConnected({this.socket});
  SIPUASocketInterface? socket;
}

class EventSocketConnecting extends EventType {
  EventSocketConnecting({this.socket});
  SIPUASocketInterface? socket;
}

class EventSocketDisconnected extends EventType {
  EventSocketDisconnected({SIPUASocketInterface? socket, this.cause});
  SIPUASocketInterface? socket;
  ErrorCause? cause;
}
