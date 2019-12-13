import 'events.dart';
import '../sip_message.dart';
import '../rtc_session.dart';
import 'package:flutter_webrtc/webrtc.dart';

class EventNewRTCSession extends EventType {
  RTCSession session;
  String originator;
  dynamic request;
  EventNewRTCSession({this.session, String originator, dynamic request});
}

class EventCallConnecting extends EventType {
  EventCallConnecting({dynamic request});
}

class EventCallEnded extends EventType {
  String originator;
  ErrorCause cause;
  IncomingRequest request;
  EventCallEnded({this.originator, this.cause, this.request});
}

class EventCallProgress extends EventType {
  String originator;
  dynamic response;
  EventCallProgress({this.originator, this.response});
}

class EventCallConfirmed extends EventType {
  String originator;
  dynamic ack;
  EventCallConfirmed({this.originator, this.ack});
}

class EventCallHold extends EventType {
  String originator;
  EventCallHold({this.originator});
}

class EventCallUnhold extends EventType {
  String originator;
  EventCallUnhold({String originator});
}

class EventCallMuted extends EventType {
  bool audio;
  bool video;
  EventCallMuted({this.audio, this.video});
}

class EventCallUnmuted extends EventType {
  bool audio;
  bool video;
  EventCallUnmuted({this.audio, this.video});
}

class EventCallAccepted extends EventType {
  String originator;
  dynamic response;
  EventCallAccepted({this.originator, this.response});
}

class EventCallFailed extends EventType {
  dynamic response;
  String originator;
  ErrorCause cause;
  dynamic request;
  String status_line;
  EventCallFailed(
      {String state,
      this.response,
      this.originator,
      MediaStream stream,
      this.cause,
      this.request,
      this.status_line});
}

class EventStream extends EventType {
  String originator;
  MediaStream stream;
  EventStream({this.originator, this.stream});
}

class EventCallRefer extends EventType {
  String aor;

  /// bool Function({Function initCallback, dynamic options}) accept;
  dynamic accept;

  /// bool Function(dynamic options) reject;
  dynamic reject;
  EventCallRefer({this.aor, this.accept, this.reject});
}
