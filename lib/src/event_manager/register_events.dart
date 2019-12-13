import 'events.dart';

class EventRegistrationExpiring extends EventType {
  EventRegistrationExpiring();
}

class EventRegistered extends EventType {
  ErrorCause cause;
  EventRegistered({this.cause});
}

class EventRegistrationFailed extends EventType {
  ErrorCause cause;
  EventRegistrationFailed({this.cause});
}

class EventUnregister extends EventType {
  ErrorCause cause;
  EventUnregister({this.cause});
}
