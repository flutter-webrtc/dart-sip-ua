import 'package:flutter_webrtc/webrtc.dart';

import 'events.dart';
import '../../sip_ua.dart';
import '../name_addr_header.dart';
import '../message.dart';
import '../rtc_session.dart';
import '../rtc_session/dtmf.dart';
import '../rtc_session/info.dart';
import '../sip_message.dart';
import '../transport.dart';
import '../transports/websocket_interface.dart';
import '../transactions/transaction_base.dart';

class EventStateChanged extends EventType {}

class EventNewTransaction extends EventType {
  TransactionBase transaction;
  EventNewTransaction({this.transaction});
}

class EventTransactionDestroyed extends EventType {
  TransactionBase transaction;
  EventTransactionDestroyed({this.transaction});
}

class EventSipEvent extends EventType {
  IncomingRequest request;
  EventSipEvent({this.request});
}

class EventOnAuthenticated extends EventType {
  OutgoingRequest request;
  EventOnAuthenticated({this.request});
}

class EventSdp extends EventType {
  String originator;
  String type;
  String sdp;
  EventSdp({this.originator, this.type, this.sdp});
}

class EventSending extends EventType {
  OutgoingRequest request;
  EventSending({this.request});
}

class EventSetRemoteDescriptionFailed extends EventType {
  dynamic exception;
  EventSetRemoteDescriptionFailed({this.exception});
}

class EventSetLocalDescriptionFailed extends EventType {
  dynamic exception;
  EventSetLocalDescriptionFailed({this.exception});
}

class EventFailedUnderScore extends EventType {
  String originator;
  ErrorCause cause;
  EventFailedUnderScore({this.originator, this.cause});
}

class EventGetUserMediaFailed extends EventType {
  dynamic exception;
  EventGetUserMediaFailed({this.exception});
}

class EventNewDTMF extends EventType {
  String originator;
  dynamic request;
  DTMF dtmf;
  EventNewDTMF({this.originator, this.request, this.dtmf});
}

class EventNewInfo extends EventType {
  String originator;
  dynamic request;
  Info info;
  EventNewInfo({this.originator, this.request, this.info});
}

class EventPeerConnection extends EventType {
  RTCPeerConnection peerConnection;
  EventPeerConnection(this.peerConnection);
}

class EventReplaces extends EventType {
  dynamic request;
  bool Function(dynamic options) accept;
  bool Function(dynamic options) reject;
  EventReplaces({this.request, this.accept, this.reject});
}

class EventUpdate extends EventType {
  dynamic request;
  bool Function(dynamic options) callback;
  bool Function(dynamic options) reject;
  EventUpdate({this.request, this.callback, this.reject});
}

class EventReinvite extends EventType {
  dynamic request;
  bool Function(dynamic options) callback;
  bool Function(dynamic options) reject;
  EventReinvite({this.request, this.callback, this.reject});
}

class EventIceCandidate extends EventType {
  RTCIceCandidate candidate;
  Future<Null> Function() ready;
  EventIceCandidate(this.candidate, this.ready);
}

class EventCreateAnswerFialed extends EventType {
  dynamic exception;
  EventCreateAnswerFialed({this.exception});
}

class EventCreateOfferFailed extends EventType {
  dynamic exception;
  EventCreateOfferFailed({this.exception});
}

class EventOnFialed extends EventType {}

class EventSucceeded extends EventType {
  String originator;
  IncomingMessage response;
  EventSucceeded({this.response, this.originator});
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
