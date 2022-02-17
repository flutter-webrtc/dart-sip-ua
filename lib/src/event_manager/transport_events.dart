import '../transports/websocket_interface.dart';
import 'events.dart';

class EventSocketConnected extends EventType {
  EventSocketConnected({this.socket});
  WebSocketInterface? socket;
}

class EventSocketConnecting extends EventType {
  EventSocketConnecting({this.socket});
  WebSocketInterface? socket;
}

class EventSocketDisconnected extends EventType {
  EventSocketDisconnected({WebSocketInterface? socket, this.cause});
  WebSocketInterface? socket;
  ErrorCause? cause;
}
