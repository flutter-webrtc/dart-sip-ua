import 'events.dart';

class EventReferTrying extends EventType {
  EventReferTrying({this.status_line, this.request});
  String? status_line;
  dynamic request;
}

class EventReferProgress extends EventType {
  EventReferProgress({this.status_line, this.request});
  String? status_line;
  dynamic request;
}

class EventReferAccepted extends EventType {
  EventReferAccepted({this.status_line, this.request});
  String? status_line;
  dynamic request;
}

class EventReferFailed extends EventType {
  EventReferFailed({this.request, this.status_line});
  dynamic request;
  String? status_line;
}

class EventReferRequestSucceeded extends EventType {
  EventReferRequestSucceeded({this.response});
  dynamic response;
}

class EventReferRequestFailed extends EventType {
  EventReferRequestFailed({this.response, this.cause});
  dynamic response;
  ErrorCause? cause;
}
