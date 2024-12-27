import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../enums.dart';
import '../rtc_session.dart';
import '../sip_message.dart';
import 'events.dart';

class CallEvent extends EventType {
  CallEvent(this.session);
  RTCSession? session;
  String? get id => session!.id;
}

class EventNewRTCSession extends CallEvent {
  EventNewRTCSession(
      {RTCSession? session, Originator? originator, dynamic request})
      : super(session);
  Originator? originator;
  dynamic request;
}

class EventCallConnecting extends CallEvent {
  EventCallConnecting({RTCSession? session, dynamic request}) : super(session);
}

class EventCallEnded extends CallEvent {
  EventCallEnded(
      {RTCSession? session, this.originator, this.cause, this.request})
      : super(session);
  Originator? originator;
  ErrorCause? cause;
  IncomingRequest? request;
}

class EventCallProgress extends CallEvent {
  EventCallProgress(
      {RTCSession? session, this.originator, this.response, this.cause})
      : super(session);
  Originator? originator;
  dynamic response;
  ErrorCause? cause;
}

class EventCallConfirmed extends CallEvent {
  EventCallConfirmed({RTCSession? session, this.originator, this.ack})
      : super(session);
  Originator? originator;
  dynamic ack;
}

class EventCallHold extends CallEvent {
  EventCallHold({RTCSession? session, this.originator}) : super(session);
  Originator? originator;
}

class EventCallUnhold extends CallEvent {
  EventCallUnhold({RTCSession? session, Originator? originator})
      : super(session);
  Originator? originator;
}

class EventCallMuted extends CallEvent {
  EventCallMuted({RTCSession? session, this.audio, this.video})
      : super(session);
  bool? audio;
  bool? video;
}

class EventCallUnmuted extends CallEvent {
  EventCallUnmuted({RTCSession? session, this.audio, this.video})
      : super(session);
  bool? audio;
  bool? video;
}

class EventCallAccepted extends CallEvent {
  EventCallAccepted({RTCSession? session, this.originator, this.response})
      : super(session);
  Originator? originator;
  dynamic response;
}

class EventCallFailed extends CallEvent {
  EventCallFailed(
      {RTCSession? session,
      String? state,
      this.response,
      this.originator,
      MediaStream? stream,
      this.cause,
      this.request,
      this.status_line})
      : super(session);
  dynamic response;
  Originator? originator;
  ErrorCause? cause;
  dynamic request;
  String? status_line;
}

class EventStream extends CallEvent {
  EventStream({RTCSession? session, this.originator, this.stream})
      : super(session);
  Originator? originator;
  MediaStream? stream;
}

class EventCallRefer extends CallEvent {
  EventCallRefer({RTCSession? session, this.aor, this.accept, this.reject})
      : super(session);
  String? aor;

  //bool Function([Function initCallback, dynamic options]) accept;
  dynamic accept;

  //bool Function([dynamic options]) reject;
  dynamic reject;
}
