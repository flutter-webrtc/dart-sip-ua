import 'events.dart';

class EventRegistrationExpiring extends EventType {
  EventRegistrationExpiring();
}

class EventRegistered extends EventType {
  EventRegistered({this.cause});
  ErrorCause? cause;
}

class EventRegistrationFailed extends EventType {
  EventRegistrationFailed({this.cause});
  ErrorCause? cause;
}

class EventUnregister extends EventType {
  EventUnregister({this.cause});
  ErrorCause? cause;
}
