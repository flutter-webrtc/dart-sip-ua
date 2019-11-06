import 'events.dart';

class EventReferTrying extends EventType {
  String status_line;
  dynamic request;
  EventReferTrying({this.status_line, this.request});
}

class EventReferProgress extends EventType {
  String status_line;
  dynamic request;
  EventReferProgress({this.status_line, this.request});
}

class EventReferAccepted extends EventType {
  String status_line;
  dynamic request;
  EventReferAccepted({this.status_line, this.request});
}

class EventReferFailed extends EventType {
  dynamic request;
  String status_line;
  EventReferFailed({this.request, this.status_line});
}

class EventReferRequestSucceeded extends EventType {
  dynamic response;
  EventReferRequestSucceeded({this.response});
}

class EventReferRequestFailed extends EventType {
  dynamic response;
  ErrorCause cause;
  EventReferRequestFailed({this.response, this.cause});
}
