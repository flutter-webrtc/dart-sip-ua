import '../sip_message.dart';
import 'events.dart';

class EventTerminated extends EventType {
  EventTerminated({this.TerminationCode, this.reason, this.retryAfter});
  int? TerminationCode;
  String? reason;
  int? retryAfter;
}

class EventPending extends EventType {}

class EventActive extends EventType {}

class EventNotify extends EventType {
  EventNotify({this.isFinal, this.request, this.body, this.contentType});
  bool? isFinal;
  IncomingRequest? request;
  String? body;
  String? contentType;
}

class EventAccepted extends EventType {}
