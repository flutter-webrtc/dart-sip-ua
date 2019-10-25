import 'package:flutter_webrtc/webrtc.dart';

import '../../sip_ua.dart';
import '../Message.dart';
import '../RTCSession.dart';
import '../RTCSession/DTMF.dart';
import '../RTCSession/Info.dart';
import '../SIPMessage.dart';
import '../Transport.dart';
import '../WebSocketInterface.dart';
import '../transactions/transaction_base.dart';

/// each EventType class can implement this method and the EventManager will call it before
/// delivering an event, thus ensuring good quality events with a fail early approach.
abstract class EventType {
  sanityCheck() {}
}

/// All of the following Event classes are named exactly the same as the strings that the old code used
/// except that they are all prefixed with Event. ie. "stateChanged" is EventStateChanged
///
/// You will see a lot of commented out fields, these fields are not referenced any where in the code.
/// In a future update I'd suggest removing them and removing the parameters associated with them and
/// thus remove a lot of unneeded code.
///
/// I've tried to infer types to help with future debugging, but unfortunately the types of "response"
/// and "request" are many and share no common hierarchy so they have
/// to remain dynamic in many places for now.
///
/// These changes will make it much easier to reason about where Events go to and come from, as well as
/// exactly what fields are available without the need to actually run the code.

class EventStateChanged extends EventType {}

class EventNewTransaction extends EventType {
  // TransactionBase transaction;
  EventNewTransaction({TransactionBase transaction});
}

class EventTransactionDestroyed extends EventType {
//  TransactionBase transaction;
  EventTransactionDestroyed({TransactionBase transaction});
}

class EventNewMessage extends EventType {
  // String state;
  //dynamic response;
  String originator;
  // MediaStream stream;
  EventNewMessage({Message message, this.originator, OutgoingRequest request});
}

class EventRegistered extends EventType {
  IncomingMessage response;
  EventRegistered({this.response});
}

class EventRegistrationFailed extends EventType {
  IncomingMessage response;
  String cause;
  EventRegistrationFailed({this.response, this.cause});
}

class EventUnregister extends EventType {
  IncomingMessage response;
  //String cause;
  EventUnregister({this.response, String cause});
}

class EventSipEvent extends EventType {
  //OutgoingRequest request;
  EventSipEvent({IncomingRequest request});
}

class EventConnected extends EventType {
  //Transport transport;
  EventConnected({Transport transport});
}

class EventConnecting extends EventType {
  //OutgoingRequest request;
  WebSocketInterface socket;

  EventConnecting({dynamic request, this.socket});
}

class EventDisconnected extends EventType {
  // WebSocketInterface socket;
  // bool error;
  EventDisconnected({WebSocketInterface socket, bool error});
}

class EventStream extends EventType {
  String originator;
  MediaStream stream;
  EventStream({this.originator, this.stream});
}

class EventOnAuthenticated extends EventType {
  OutgoingRequest request;
  EventOnAuthenticated({this.request});
}

class EventSdp extends EventType {
//  String originator;
//  String type;
//  String sdp;
  EventSdp({String originator, String type, String sdp});
}

class EventSending extends EventType {
  // dynamic requset;
  EventSending({OutgoingRequest request});
}

class EventSetRemoteDescriptionFailed extends EventType {
  // dynamic exception;
  EventSetRemoteDescriptionFailed({dynamic exception});
}

class EventSetLocalDescriptionFailed extends EventType {
//  dynamic exception;
  EventSetLocalDescriptionFailed({dynamic exception});
}

class EventFailedUnderScore extends EventType {
//  String originator;
  String cause;
  dynamic message;
  EventFailedUnderScore({String originator, this.cause, this.message});
}

class EventGetUserMediaFailed extends EventType {
//  dynamic exception;
  EventGetUserMediaFailed({dynamic exception});
}

class EventNewDTMF extends EventType {
//  String originator;
  // OutgoingRequest request;
  // DTMF dtmf;
  EventNewDTMF({String originator, OutgoingRequest request, DTMF dtmf});
}

class EventNewInfo extends EventType {
//  String originator;
//  OutgoingRequest request;
  // Info info;
  EventNewInfo({String originator, OutgoingRequest request, Info info});
}

class EventPeerConnection extends EventType {
//  RTCPeerConnection peerConnection;
  EventPeerConnection(RTCPeerConnection peerConnection);
}

class EventReplaces extends EventType {
//  OutgoingRequest request;
//  bool Function(dynamic options) accept;
//  bool Function(dynamic options) reject;
  EventReplaces(
      {String request,
      bool Function(dynamic options) accept,
      bool Function(dynamic options) reject});
}

class EventConfirmed extends EventType {
//  String originator;
//  String ack;
  EventConfirmed({String originator, dynamic ack});
}

class EventUpdate extends EventType {
//  OutgoingRequest request;
//  bool Function(dynamic options) callback;
//  bool Function(dynamic options) reject;
  EventUpdate(
      {IncomingRequest request,
      bool Function(dynamic options) callback,
      bool Function(dynamic options) reject});
}

class EventReinvite extends EventType {
  // OutgoingRequest request;
//  bool Function(dynamic options) callback;
//  bool Function(dynamic options) reject;
  EventReinvite(
      {String request,
      bool Function(dynamic options) callback,
      bool Function(dynamic options) reject});
}

class EventIceCandidate extends EventType {
//  RTCIceCandidate candidate;
//  Future<Null> Function() ready;
  EventIceCandidate(RTCIceCandidate candidate, Future<Null> Function() ready);
}

class EventCreateAnswerFialed extends EventType {
//  dynamic exception;
  EventCreateAnswerFialed({dynamic exception});
}

class EventCreateOfferFailed extends EventType {
//  dynamic exception;
  EventCreateOfferFailed({dynamic exception});
}

class EventRefer extends EventType {
//  OutgoingRequest request;
  // bool Function(dynamic arg1, dynamic arg2) accept2;
  // bool Function(dynamic options) reject;
  EventRefer(
      {String request,
      bool Function(dynamic arg1, dynamic arg2) accept2,
      bool Function(dynamic options) reject});
}

class EventEnded extends EventType {
  String originator;
  String cause;
  IncomingRequest request;
//  dynamic message;
  EventEnded({this.originator, this.cause, this.request});
}

class EventOnFialed extends EventType {}

class EventTrying extends EventType {
//  OutgoingRequest request;
//  String status_line;
  EventTrying({String request, String status_line});
}

class EventProgress extends EventType {
  // OutgoingRequest request;
  // String status_line;
  String originator;
  IncomingMessage response;
  EventProgress(
      {String request, String status_line, this.originator, this.response});
}

class EventAccepted extends EventType {
  // OutgoingRequest request;
  // String status_line;
  // String originator;
  IncomingMessage response;
  EventAccepted(
      {String request, String status_line, String originator, this.response});
}

class EventCallAccepted extends EventType {}

class EventFailed extends EventType {
  // String state;
  IncomingMessage response;
  String originator;
  // MediaStream stream;
  String cause;
  // dynamic message;
  // OutgoingRequest request;
  // String status_line;
  EventFailed(
      {String state,
      this.response,
      this.originator,
      MediaStream stream,
      this.cause,
      String message,
      OutgoingRequest request,
      String status_line});
}

class EventRequestSucceeded extends EventType {
  //dynamic response;
  EventRequestSucceeded({dynamic response});
}

class EventRequestFailed extends EventType {
  //dynamic response;
  //String cause;
  EventRequestFailed({dynamic response, String cause});
}

class EventSucceeded extends EventType {
  // String state;
  // dynamic response;
  // String originator;
  // MediaStream stream;
  // String cause;
  EventSucceeded(
      {String state,
      IncomingMessage response,
      String originator,
      MediaStream stream,
      String cause});
}

class EventGetusermediafailed extends EventType {
  // dynamic exception;
  EventGetusermediafailed({dynamic exception});
}

class EventHold extends EventType {
  String originator;
  EventHold({this.originator});
}

class EventUnhold extends EventType {
  String originator;
  EventUnhold({String originator});
}

class EventMuted extends EventType {
  bool audio;
  bool video;
  EventMuted({this.audio, this.video});
}

class EventUnmuted extends EventType {
  bool audio;
  bool video;
  EventUnmuted({this.audio, this.video});
}

class EventNewRTCSession extends EventType {
  RTCSession session;
  // String originator;
  // OutgoingRequest request;
  EventNewRTCSession({this.session, String originator, dynamic request});
}

class EventOnTransportError extends EventType {
  EventOnTransportError() : super();
}

class EventOnRequestTimeout extends EventType {
  IncomingMessage request;
  EventOnRequestTimeout({this.request});
}

class EventOnReceiveResponse extends EventType {
  IncomingResponse response;
  EventOnReceiveResponse({this.response});
  sanityCheck() {
    assert(response != null);
  }
}

class EventOnDialogError extends EventType {
  IncomingMessage response;
  EventOnDialogError({this.response});
}

class EventOnSuccessResponse extends EventType {
  IncomingMessage response;
  EventOnSuccessResponse({this.response});
}

class EventOnErrorResponse extends EventType {
  IncomingMessage response;
  EventOnErrorResponse({this.response});
}

class EventRegistrationExpiring extends EventType {
  EventRegistrationExpiring();
}
