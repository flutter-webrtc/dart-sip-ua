import 'events.dart';
import '../sip_message.dart';
import '../rtc_session.dart';
import 'package:flutter_webrtc/webrtc.dart';

class CallEvent extends EventType {
  RTCSession session;
  String get id => session.id;
  CallEvent(this.session);
}

class EventNewRTCSession extends CallEvent {
  String originator;
  dynamic request;
  EventNewRTCSession({RTCSession session, String originator, dynamic request})
      : super(session);
}

class EventCallConnecting extends CallEvent {
  EventCallConnecting({RTCSession session, dynamic request}) : super(session);
}

class EventCallEnded extends CallEvent {
  String originator;
  ErrorCause cause;
  IncomingRequest request;
  EventCallEnded(
      {RTCSession session, this.originator, this.cause, this.request})
      : super(session);
}

class EventCallProgress extends CallEvent {
  String originator;
  dynamic response;
  EventCallProgress({RTCSession session, this.originator, this.response})
      : super(session);
}

class EventCallConfirmed extends CallEvent {
  String originator;
  dynamic ack;
  EventCallConfirmed({RTCSession session, this.originator, this.ack})
      : super(session);
}

class EventCallHold extends CallEvent {
  String originator;
  EventCallHold({RTCSession session, this.originator}) : super(session);
}

class EventCallUnhold extends CallEvent {
  String originator;
  EventCallUnhold({RTCSession session, String originator}) : super(session);
}

class EventCallMuted extends CallEvent {
  bool audio;
  bool video;
  EventCallMuted({RTCSession session, this.audio, this.video}) : super(session);
}

class EventCallUnmuted extends CallEvent {
  bool audio;
  bool video;
  EventCallUnmuted({RTCSession session, this.audio, this.video})
      : super(session);
}

class EventCallAccepted extends CallEvent {
  String originator;
  dynamic response;
  EventCallAccepted({RTCSession session, this.originator, this.response})
      : super(session);
}

class EventCallFailed extends CallEvent {
  dynamic response;
  String originator;
  ErrorCause cause;
  dynamic request;
  String status_line;
  EventCallFailed(
      {RTCSession session,
      String state,
      this.response,
      this.originator,
      MediaStream stream,
      this.cause,
      this.request,
      this.status_line})
      : super(session);
}

class EventStream extends CallEvent {
  String originator;
  MediaStream stream;
  EventStream({RTCSession session, this.originator, this.stream})
      : super(session);
}

class EventCallRefer extends CallEvent {
  String aor;

  /// bool Function({Function initCallback, dynamic options}) accept;
  dynamic accept;

  /// bool Function(dynamic options) reject;
  dynamic reject;
  EventCallRefer({RTCSession session, this.aor, this.accept, this.reject})
      : super(session);
}
