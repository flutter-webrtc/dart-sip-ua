import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sdp_transform/sdp_transform.dart' as sdp_transform;

import '../sip_ua.dart';
import 'constants.dart' as DartSIP_C;
import 'constants.dart';
import 'dialog.dart';
import 'event_manager/event_manager.dart';
import 'event_manager/internal_events.dart';
import 'exceptions.dart' as Exceptions;
import 'logger.dart';
import 'name_addr_header.dart';
import 'request_sender.dart';
import 'rtc_session/dtmf.dart' as RTCSession_DTMF;
import 'rtc_session/dtmf.dart';
import 'rtc_session/info.dart' as RTCSession_Info;
import 'rtc_session/info.dart';
import 'rtc_session/refer_notifier.dart';
import 'rtc_session/refer_subscriber.dart';
import 'timers.dart';
import 'transactions/transaction_base.dart';
import 'ua.dart';
import 'utils.dart' as utils;

enum RtcSessionState {
  none, // STATUS_NULL
  inviteSent, // STATUS_INVITE_SENT
  provisionalResponse, // STATUS_1XX_RECEIVED
  inviteReceived, // STATUS_INVITE_RECEIVED
  waitingForAnswer, // STATUS_WAITING_FOR_ANSWER
  answered, // STATUS_ANSWERED
  waitingForAck, // STATUS_WAITING_FOR_ACK
  canceled, // STATUS_CANCELED
  terminated, // STATUS_TERMINATED
  confirmed, // STATUS_CONFIRMED
}

/**
 * Local variables.
 */
const List<String?> holdMediaTypes = <String?>['audio', 'video'];

class SIPTimers {
  Timer? ackTimer;
  Timer? expiresTimer;
  Timer? invite2xxTimer;
  Timer? userNoAnswerTimer;
}

class RFC4028Timers {
  RFC4028Timers(this.enabled, this.refreshMethod, this.defaultExpires,
      this.currentExpires, this.running, this.refresher, this.timer);
  bool enabled;
  SipMethod refreshMethod;
  int? defaultExpires;
  int? currentExpires;
  bool running;
  bool refresher;
  Timer? timer;
}

class RTCSession extends EventManager implements Owner {
  RTCSession(this._ua) {
    logger.d('new');
    // Session Timers (RFC 4028).
    _sessionTimers = RFC4028Timers(
        _ua.configuration.session_timers,
        _ua.configuration.session_timers_refresh_method,
        DartSIP_C.SESSION_EXPIRES,
        null,
        false,
        false,
        null);

    receiveRequest = _receiveRequest;
  }

  final UA _ua;

  String? _id;
  RtcSessionState _state = RtcSessionState.none;
  Dialog? _dialog;
  final Map<String?, Dialog> _earlyDialogs = <String?, Dialog>{};
  String? _contact;
  String? _from_tag;
  String? get from_tag => _from_tag;
  String? _to_tag;
  String? get to_tag => _to_tag;

  // The RTCPeerConnection instance (public attribute).
  RTCPeerConnection? _connection;

  // RTPSender List
  final List<RTCRtpSender> _senders = <RTCRtpSender>[];

  // Incoming/Outgoing request being currently processed.
  dynamic _request;

  // Cancel state for initial outgoing request.
  bool _is_canceled = false;
  String? _cancel_reason = '';

  // RTCSession confirmation flag.
  bool _is_confirmed = false;

  // Is late SDP being negotiated.
  bool _late_sdp = false;

  // Default rtcOfferConstraints and rtcAnswerConstrainsts (passed in connect() or answer()).
  Map<String, dynamic>? _rtcOfferConstraints;
  Map<String, dynamic>? _rtcAnswerConstraints;

  // Local MediaStream.
  MediaStream? _localMediaStream;
  bool _localMediaStreamLocallyGenerated = false;

  // Flag to indicate PeerConnection ready for actions.
  bool _rtcReady = true;

  Timer? _iceDisconnectTimer;
  bool _isAttemptingIceRestart = false;

  // SIP Timers.
  final SIPTimers _timers = SIPTimers();

  // Session info.
  Direction? _direction;
  NameAddrHeader? _local_identity;
  NameAddrHeader? _remote_identity;
  DateTime? _start_time;
  DateTime? _end_time;
  String? _tones;

  // Mute/Hold state.
  bool _audioMuted = false;
  bool _videoMuted = false;
  bool _localHold = false;
  bool _remoteHold = false;

  late RFC4028Timers _sessionTimers;

  // Map of ReferSubscriber instances indexed by the REFER's CSeq number.
  final Map<int?, ReferSubscriber> _referSubscribers =
      <int?, ReferSubscriber>{};

  // Custom session empty object for high level use.
  Map<String, dynamic>? data = <String, dynamic>{};

  RTCIceGatheringState? _iceGatheringState;

  Future<void> dtmfFuture = (Completer<void>()..complete()).future;

  @override
  late Function(IncomingRequest) receiveRequest;

  /**
   * User API
   */

  // Expose session failed/ended causes as a property of the RTCSession instance.
  Type get causes => DartSIP_C.CausesType;

  String? get id => _id;

  dynamic get request => _request;

  RTCPeerConnection? get connection => _connection;

  @override
  int get TerminatedCode => RtcSessionState.terminated.index;

  RTCDTMFSender? get dtmfSender => _senders
      .firstWhereOrNull((RTCRtpSender item) =>
          item.track != null && item.track!.kind == 'audio')
      ?.dtmfSender;

  String? get contact => _contact;

  Direction? get direction => _direction;

  NameAddrHeader? get local_identity => _local_identity;

  NameAddrHeader? get remote_identity => _remote_identity;

  DateTime? get start_time => _start_time;

  DateTime? get end_time => _end_time;

  @override
  UA get ua => _ua;

  @override
  int get status => _state.index;

  RtcSessionState get state => _state;

  bool isInProgress() {
    switch (_state) {
      case RtcSessionState.none:
      case RtcSessionState.inviteSent:
      case RtcSessionState.provisionalResponse:
      case RtcSessionState.inviteReceived:
      case RtcSessionState.waitingForAnswer:
        return true;
      default:
        return false;
    }
  }

  bool isEstablished() {
    switch (_state) {
      case RtcSessionState.answered:
      case RtcSessionState.waitingForAck:
      case RtcSessionState.confirmed:
        return true;
      default:
        return false;
    }
  }

  bool isEnded() {
    switch (_state) {
      case RtcSessionState.canceled:
      case RtcSessionState.terminated:
        return true;
      default:
        return false;
    }
  }

  Map<String, dynamic> isMuted() {
    return <String, dynamic>{'audio': _audioMuted, 'video': _videoMuted};
  }

  Map<String, dynamic> isOnHold() {
    return <String, dynamic>{'local': _localHold, 'remote': _remoteHold};
  }

  void connect(dynamic target,
      [Map<String, dynamic>? options,
      InitSuccessCallback? initCallback]) async {
    logger.d('connect()');

    options = options ?? <String, dynamic>{};
    dynamic originalTarget = target;
    EventManager eventHandlers = options['eventHandlers'] ?? EventManager();
    List<dynamic> extraHeaders = utils.cloneArray(options['extraHeaders']);
    Map<String, dynamic> mediaConstraints = options['mediaConstraints'] ??
        <String, dynamic>{'audio': true, 'video': true};
    MediaStream? mediaStream = options['mediaStream'];
    Map<String, dynamic> pcConfig =
        options['pcConfig'] ?? <String, dynamic>{'iceServers': <dynamic>[]};
    Map<String, dynamic> rtcConstraints =
        options['rtcConstraints'] ?? <String, dynamic>{};
    Map<String, dynamic> rtcOfferConstraints =
        options['rtcOfferConstraints'] ?? <String, dynamic>{};
    _rtcOfferConstraints = rtcOfferConstraints;
    _rtcAnswerConstraints =
        options['rtcAnswerConstraints'] ?? <String, dynamic>{};
    data = options['data'] ?? data;
    data?['video'] = !(options['mediaConstraints']['video'] == false);

    // Check target.
    if (target == null) {
      throw Exceptions.TypeError('Not enough arguments');
    }

    // Check Session Status.
    if (_state != RtcSessionState.none) {
      throw Exceptions.InvalidStateError(_state.name);
    }

    // Check WebRTC support.
    // TODO(cloudwebrtc): change support for flutter-webrtc
    //if (RTCPeerConnection == null)
    //{
    //  throw Exceptions.NotSupportedError('WebRTC not supported');
    //}

    // Check target validity.
    target = _ua.normalizeTarget(target);
    if (target == null) {
      throw Exceptions.TypeError('Invalid target: $originalTarget');
    }

    // Session Timers.
    if (_sessionTimers.enabled) {
      if (utils.isDecimal(options['sessionTimersExpires'])) {
        if (options['sessionTimersExpires'] >= DartSIP_C.MIN_SESSION_EXPIRES) {
          _sessionTimers.defaultExpires = options['sessionTimersExpires'];
        } else {
          _sessionTimers.defaultExpires = DartSIP_C.SESSION_EXPIRES;
        }
      }
    }

    // Set event handlers.
    addAllEventHandlers(eventHandlers);

    // Session parameter initialization.
    _from_tag = utils.newTag();

    // Set anonymous property.
    bool anonymous = options['anonymous'] ?? false;
    Map<String, dynamic> requestParams = <String, dynamic>{
      'from_tag': _from_tag,
      'to_display_name': options['to_display_name'] ?? '',
      'call_id': options['call_id'] ?? null,
    };
    _ua.contact!.anonymous = anonymous;
    _ua.contact!.outbound = true;
    _contact = _ua.contact.toString();

    bool isFromUriOptionPresent = options['from_uri'] != null;

    //set from_uri and from_display_name if present
    if (isFromUriOptionPresent) {
      requestParams['from_display_name'] = options['from_display_name'] ?? '';
      requestParams['from_uri'] = URI.parse(options['from_uri']);
      extraHeaders
          .add('P-Preferred-Identity: ${_ua.configuration.uri.toString()}');
    }

    if (anonymous) {
      requestParams['from_display_name'] = 'Anonymous';
      requestParams['from_uri'] = URI('sip', 'anonymous', 'anonymous.invalid');
      extraHeaders
          .add('P-Preferred-Identity: ${_ua.configuration.uri.toString()}');
      extraHeaders.add('Privacy: id');
    }

    extraHeaders.add('Contact: $_contact');
    extraHeaders.add('Content-Type: application/sdp');
    if (_sessionTimers.enabled) {
      extraHeaders.add('Session-Expires: ${_sessionTimers.defaultExpires}');
    }

    _request =
        InitialOutgoingInviteRequest(target, _ua, requestParams, extraHeaders);

    _id = _request.call_id + _from_tag;

    // Create a RTCPeerConnection instance.
    await _createRTCConnection(pcConfig, rtcConstraints);

    // Set internal properties.
    _direction = Direction.outgoing;
    _local_identity = _request.from;
    _remote_identity = _request.to;

    // User explicitly provided a newRTCSession callback for this session.
    if (initCallback != null) {
      initCallback(this);
    }

    _newRTCSession(Originator.local, _request);
    await _sendInitialRequest(
        pcConfig, mediaConstraints, rtcOfferConstraints, mediaStream);
  }

  void init_incoming(IncomingRequest request,
      [Function(RTCSession)? initCallback]) {
    logger.d('init_incoming()');

    int? expires;
    String? contentType = request.getHeader('Content-Type');

    // Check body and content type.
    if (request.body != null && (contentType != 'application/sdp')) {
      request.reply(415);
      return;
    }

    // Session parameter initialization.
    _state = RtcSessionState.inviteReceived;
    _from_tag = request.from_tag;
    _id = request.call_id! + _from_tag!;
    _request = request;
    _contact = _ua.contact.toString();

    // Get the Expires header value if exists.
    if (request.hasHeader('expires')) {
      try {
        expires = (request.getHeader('expires') is num
                ? request.getHeader('expires')
                : num.tryParse(request.getHeader('expires'))!) *
            1000;
      } catch (e) {
        logger.e(
            'Invalid Expires header value: ${request.getHeader('expires')}, error $e');
      }
    }

    /* Set the to_tag before
     * replying a response code that will create a dialog.
     */
    request.to_tag = utils.newTag();

    // An error on dialog creation will fire 'failed' event.
    if (!_createDialog(request, 'UAS', true)) {
      request.reply(500, 'Missing Contact header field');
      return;
    }

    if (request.body != null) {
      _late_sdp = false;
    } else {
      _late_sdp = true;
    }

    _state = RtcSessionState.waitingForAnswer;

    // Set userNoAnswerTimer.
    _timers.userNoAnswerTimer = setTimeout(() {
      request.reply(408);
      _failed(Originator.local, null, null, null, 408,
          DartSIP_C.CausesType.NO_ANSWER, 'No Answer');
    }, _ua.configuration.no_answer_timeout);

    /* Set expiresTimer
     * RFC3261 13.3.1
     */
    if (expires != null) {
      _timers.expiresTimer = setTimeout(() {
        if (_state == RtcSessionState.waitingForAnswer) {
          request.reply(487);
          _failed(Originator.system, null, null, null, 487,
              DartSIP_C.CausesType.EXPIRES, 'Timeout');
        }
      }, expires);
    }

    // Set internal properties.
    _direction = Direction.incoming;
    _local_identity = request.to;
    _remote_identity = request.from;

    // A init callback was specifically defined.
    if (initCallback != null) {
      initCallback(this);
    }

    // Fire 'newRTCSession' event.
    _newRTCSession(Originator.remote, request);

    // The user may have rejected the call in the 'newRTCSession' event.
    if (_state == RtcSessionState.terminated) {
      return;
    }

    // Reply 180.
    request.reply(180, null, <dynamic>['Contact: $_contact']);

    // Fire 'progress' event.
    // TODO(cloudwebrtc): Document that 'response' field in 'progress' event is null for incoming calls.
    _progress(Originator.local, null);
  }

  /**
   * Answer the call.
   */
  void answer(Map<String, dynamic> options) async {
    logger.d('answer()');
    dynamic request = _request;
    List<dynamic> extraHeaders = utils.cloneArray(options['extraHeaders']);
    Map<String, dynamic> mediaConstraints =
        options['mediaConstraints'] ?? <String, dynamic>{};
    MediaStream? mediaStream = options['mediaStream'] ?? null;
    Map<String, dynamic> pcConfig =
        options['pcConfig'] ?? <String, dynamic>{'iceServers': <dynamic>[]};
    Map<String, dynamic> rtcConstraints =
        options['rtcConstraints'] ?? <String, dynamic>{};
    Map<String, dynamic> rtcAnswerConstraints =
        options['rtcAnswerConstraints'] ?? <String, dynamic>{};

    List<MediaStreamTrack> tracks;
    bool peerHasAudioLine = false;
    bool peerHasVideoLine = false;
    bool peerOffersFullAudio = false;
    bool peerOffersFullVideo = false;

    // In future versions, unified-plan will be used by default
    String? sdpSemantics = 'unified-plan';
    if (pcConfig['sdpSemantics'] != null) {
      sdpSemantics = pcConfig['sdpSemantics'];
    }

    _rtcAnswerConstraints = rtcAnswerConstraints;
    _rtcOfferConstraints = options['rtcOfferConstraints'] ?? null;

    data = options['data'] ?? data;

    // Check Session Direction and Status.
    if (_direction != Direction.incoming) {
      throw Exceptions.NotSupportedError(
          '"answer" not supported for outgoing RTCSession');
    }

    // Check Session status.
    if (_state != RtcSessionState.waitingForAnswer) {
      throw Exceptions.InvalidStateError(_state.name);
    }

    // Session Timers.
    if (_sessionTimers.enabled) {
      if (utils.isDecimal(options['sessionTimersExpires'])) {
        if (options['sessionTimersExpires'] >= DartSIP_C.MIN_SESSION_EXPIRES) {
          _sessionTimers.defaultExpires = options['sessionTimersExpires'];
        } else {
          _sessionTimers.defaultExpires = DartSIP_C.SESSION_EXPIRES;
        }
      }
    }

    _state = RtcSessionState.answered;

    // An error on dialog creation will fire 'failed' event.
    if (!_createDialog(request, 'UAS')) {
      request.reply(500, 'Error creating dialog');

      return;
    }

    clearTimeout(_timers.userNoAnswerTimer);
    extraHeaders.insert(0, 'Contact: $_contact');

    // Determine incoming media from incoming SDP offer (if any).
    Map<String, dynamic> sdp = request.parseSDP();

    // Make sure sdp['media'] is an array, not the case if there is only one media.
    if (sdp['media'] is! List) {
      sdp['media'] = <dynamic>[sdp['media']];
    }

    // Go through all medias in SDP to find offered capabilities to answer with.
    for (Map<String, dynamic> m in sdp['media']) {
      if (m['type'] == 'audio') {
        peerHasAudioLine = true;
        if (m['direction'] == null || m['direction'] == 'sendrecv') {
          peerOffersFullAudio = true;
        }
      }
      if (m['type'] == 'video') {
        peerHasVideoLine = true;
        if (m['direction'] == null || m['direction'] == 'sendrecv') {
          peerOffersFullVideo = true;
        }
      }
    }

    // Remove audio from mediaStream if suggested by mediaConstraints.
    if (mediaStream != null && mediaConstraints['audio'] == false) {
      tracks = mediaStream.getAudioTracks();
      for (MediaStreamTrack track in tracks) {
        mediaStream.removeTrack(track);
      }
    }

    // Remove video from mediaStream if suggested by mediaConstraints.
    if (mediaStream != null && mediaConstraints['video'] == false) {
      tracks = mediaStream.getVideoTracks();
      for (MediaStreamTrack track in tracks) {
        mediaStream.removeTrack(track);
      }
    }

    // Set audio constraints based on incoming stream if not supplied.
    if (mediaStream == null && mediaConstraints['audio'] == null) {
      mediaConstraints['audio'] = peerOffersFullAudio;
    }

    // Set video constraints based on incoming stream if not supplied.
    if (mediaStream == null && mediaConstraints['video'] == null) {
      mediaConstraints['video'] = peerOffersFullVideo;
    }

    // Don't ask for audio if the incoming offer has no audio section.
    if (mediaStream == null && !peerHasAudioLine) {
      mediaConstraints['audio'] = false;
    }

    // Don't ask for video if the incoming offer has no video section.
    if (mediaStream == null && !peerHasVideoLine) {
      mediaConstraints['video'] = false;
    }

    // Create a RTCPeerConnection instance.
    // TODO(cloudwebrtc): This may throw an error, should react.
    await _createRTCConnection(pcConfig, rtcConstraints);

    MediaStream? stream;
    // A local MediaStream is given, use it.
    if (mediaStream != null) {
      stream = mediaStream;
      emit(EventStream(
          session: this, originator: Originator.local, stream: stream));
    }
    // Audio and/or video requested, prompt getUserMedia.
    else if (mediaConstraints['audio'] != null ||
        mediaConstraints['video'] != null) {
      _localMediaStreamLocallyGenerated = true;
      try {
        stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
        emit(EventStream(
            session: this, originator: Originator.local, stream: stream));
      } catch (error) {
        if (_state == RtcSessionState.terminated) {
          throw Exceptions.InvalidStateError('terminated');
        }
        request.reply(480);
        _failed(
            Originator.local,
            null,
            null,
            null,
            480,
            DartSIP_C.CausesType.USER_DENIED_MEDIA_ACCESS,
            'User Denied Media Access');
        logger.e('emit "getusermediafailed" [error:${error.toString()}]');
        emit(EventGetUserMediaFailed(exception: error));
        throw Exceptions.InvalidStateError('getUserMedia() failed');
      }
    }

    if (_state == RtcSessionState.terminated) {
      throw Exceptions.InvalidStateError('terminated');
    }

    // Attach MediaStream to RTCPeerconnection.
    _localMediaStream = stream;

    if (stream != null) {
      switch (sdpSemantics) {
        case 'unified-plan':
          stream.getTracks().forEach((MediaStreamTrack track) async {
            RTCRtpSender sender = await _connection!.addTrack(track, stream!);
            _senders.add(sender);
          });
          break;
        case 'plan-b':
          _connection!.addStream(stream);
          break;
        default:
          logger.e('Unkown sdp semantics $sdpSemantics');
          throw Exceptions.NotReadyError('Unkown sdp semantics $sdpSemantics');
      }
    }

    // Set remote description.
    if (_late_sdp) return;

    logger.d('emit "sdp"');
    final String? processedSDP = _sdpOfferToWebRTC(request.body);
    emit(EventSdp(
        originator: Originator.remote, type: SdpType.offer, sdp: processedSDP));

    RTCSessionDescription offer =
        RTCSessionDescription(processedSDP, SdpType.offer.name);
    try {
      await _connection!.setRemoteDescription(offer);
    } catch (error) {
      request.reply(488);
      _failed(
          Originator.system,
          null,
          null,
          null,
          488,
          DartSIP_C.CausesType.WEBRTC_ERROR,
          'SetRemoteDescription(offer) failed');
      logger.e(
          'emit "peerconnection:setremotedescriptionfailed" [error:${error.toString()}]');
      emit(EventSetRemoteDescriptionFailed(exception: error));
      throw Exceptions.TypeError(
          'peerconnection.setRemoteDescription() failed');
    }

    // Create local description.
    if (_state == RtcSessionState.terminated) {
      throw Exceptions.InvalidStateError('terminated');
    }

    // TODO(cloudwebrtc): Is this event already useful?
    _connecting(request);
    RTCSessionDescription desc;
    try {
      if (!_late_sdp) {
        desc =
            await _createLocalDescription(SdpType.answer, rtcAnswerConstraints);
      } else {
        desc =
            await _createLocalDescription(SdpType.offer, _rtcOfferConstraints);
      }
    } catch (e) {
      request.reply(500);
      throw Exceptions.TypeError('_createLocalDescription() failed');
    }

    if (_state == RtcSessionState.terminated) {
      throw Exceptions.InvalidStateError('terminated');
    }

    // Send reply.
    try {
      _handleSessionTimersInIncomingRequest(request, extraHeaders);
      request.reply(200, null, extraHeaders, desc.sdp, () {
        _state = RtcSessionState.waitingForAck;
        _setInvite2xxTimer(request, desc.sdp);
        _setACKTimer();
        _accepted(Originator.local);
      }, () {
        _failed(Originator.system, null, null, null, 500,
            DartSIP_C.CausesType.CONNECTION_ERROR, 'Transport Error');
      });
    } catch (error, s) {
      if (_state == RtcSessionState.terminated) {
        return;
      }
      logger.e('Failed to answer(): ${error.toString()}',
          error: error, stackTrace: s);
    }
  }

  /**
   * Terminate the call.
   */
  void terminate([Map<String, dynamic>? options]) {
    logger.d('terminate()');

    options = options ?? <String, dynamic>{};

    Object cause = options['cause'] ?? DartSIP_C.CausesType.BYE;

    List<dynamic> extraHeaders = options['extraHeaders'] != null
        ? utils.cloneArray(options['extraHeaders'])
        : <dynamic>[];
    Object? body = options['body'];

    String? cancel_reason;
    int? status_code = options['status_code'] as int?;
    String? reason_phrase = options['reason_phrase'] as String?;

    // Check Session Status.
    if (_state == RtcSessionState.terminated) {
      throw Exceptions.InvalidStateError(_state.name);
    }

    switch (_state) {
      // - UAC -
      case RtcSessionState.none:
      case RtcSessionState.inviteSent:
      case RtcSessionState.provisionalResponse:
        logger.d('canceling session');

        if (status_code != null && (status_code < 200 || status_code >= 700)) {
          throw Exceptions.TypeError('Invalid status_code: $status_code');
        } else if (status_code != null) {
          reason_phrase = reason_phrase ?? DartSIP_C.REASON_PHRASE[status_code];
          cancel_reason = 'SIP ;cause=$status_code ;text="$reason_phrase"';
        }

        // Check Session Status.
        if (_state == RtcSessionState.none ||
            _state == RtcSessionState.inviteSent) {
          _is_canceled = true;
          _cancel_reason = cancel_reason;
        } else if (_state == RtcSessionState.provisionalResponse) {
          _request.cancel(cancel_reason ?? '');
        }

        _state = RtcSessionState.canceled;
        cancel_reason = cancel_reason ?? 'Canceled by local';
        status_code = status_code ?? 100;
        _failed(Originator.local, null, null, null, status_code,
            DartSIP_C.CausesType.CANCELED, cancel_reason);

        break;
      // - UAS -
      case RtcSessionState.waitingForAnswer:
      case RtcSessionState.answered:
        logger.d('rejecting session');

        status_code = status_code ?? 480;

        if (status_code < 300 || status_code >= 700) {
          throw Exceptions.InvalidStateError(
              'Invalid status_code: $status_code');
        }

        _request.reply(status_code, reason_phrase, extraHeaders, body);
        _failed(Originator.local, null, null, null, status_code,
            DartSIP_C.CausesType.REJECTED, reason_phrase);
        break;
      case RtcSessionState.waitingForAck:
      case RtcSessionState.confirmed:
        logger.d('terminating session');

        reason_phrase = options['reason_phrase'] as String? ??
            DartSIP_C.REASON_PHRASE[status_code ?? 0];

        if (status_code != null && (status_code < 200 || status_code >= 700)) {
          throw Exceptions.InvalidStateError(
              'Invalid status_code: $status_code');
        } else if (status_code != null) {
          extraHeaders
              .add('Reason: SIP ;case=$status_code; text="$reason_phrase"');
        }

        /* RFC 3261 section 15 (Terminating a session):
          *
          * "...the callee's UA MUST NOT send a BYE on a confirmed dialog
          * until it has received an ACK for its 2xx response or until the server
          * transaction times out."
          */
        if (_state == RtcSessionState.waitingForAck &&
            _direction == Direction.incoming &&
            _request.server_transaction.state != TransactionState.TERMINATED) {
          /// Save the dialog for later restoration.
          Dialog dialog = _dialog!;

          // Send the BYE as soon as the ACK is received...
          receiveRequest = (IncomingMessage request) {
            if (request.method == SipMethod.ACK) {
              sendRequest(
                SipMethod.BYE,
                <String, dynamic>{'extraHeaders': extraHeaders, 'body': body},
              );
              dialog.terminate();
            }
          };

          // .., or when the INVITE transaction times out
          _request.server_transaction.on(EventStateChanged(),
              (EventStateChanged state) {
            if (_request.server_transaction.state ==
                TransactionState.TERMINATED) {
              sendRequest(SipMethod.BYE, <String, dynamic>{
                'extraHeaders': extraHeaders,
                'body': body
              });
              dialog.terminate();
            }
          });

          _ended(
              Originator.local,
              null,
              ErrorCause(
                cause: cause as String?,
                status_code: status_code,
                reason_phrase: reason_phrase,
              ));

          // Restore the dialog into 'this' in order to be able to send the in-dialog BYE :-).
          _dialog = dialog;

          // Restore the dialog into 'ua' so the ACK can reach 'this' session.
          _ua.newDialog(dialog);
        } else {
          sendRequest(SipMethod.BYE,
              <String, dynamic>{'extraHeaders': extraHeaders, 'body': body});
          reason_phrase = reason_phrase ?? 'Terminated by local';
          status_code = status_code ?? 200;
          _ended(
              Originator.local,
              null,
              ErrorCause(
                  cause: cause as String?,
                  status_code: status_code,
                  reason_phrase: reason_phrase));
        }
        break;
      default:
        break;
    }
  }

  /// tones may be a single character or a string of dtmf digits
  void sendDTMF(dynamic tones, [Map<String, dynamic>? options]) {
    logger.d('sendDTMF() | tones: ${tones.toString()}');

    options = options ?? <String, dynamic>{};

    DtmfMode mode = _ua.configuration.dtmf_mode;

    // sensible defaults
    int duration = options['duration'] ?? RTCSession_DTMF.C.DEFAULT_DURATION;
    int interToneGap =
        options['interToneGap'] ?? RTCSession_DTMF.C.DEFAULT_INTER_TONE_GAP;
    int sendInterval = options['sendInterval'] ?? duration + interToneGap;

    if (tones == null) {
      throw Exceptions.TypeError('Not enough arguments');
    }

    // Check Session Status.
    if (_state != RtcSessionState.confirmed &&
        _state != RtcSessionState.waitingForAck) {
      throw Exceptions.InvalidStateError(_state);
    }

    // Convert to string.
    if (tones is num) {
      tones = tones.toString();
    }

    // Check tones.
    if (tones == null ||
        tones is! String ||
        !tones.contains(RegExp(r'^[0-9A-DR#*,]+$', caseSensitive: false))) {
      throw Exceptions.TypeError('Invalid tones: ${tones.toString()}');
    }

    // Check duration.
    if (duration == null) {
      duration = RTCSession_DTMF.C.DEFAULT_DURATION;
    } else if (duration < RTCSession_DTMF.C.MIN_DURATION) {
      logger.d(
          '"duration" value is lower than the minimum allowed, setting it to ${RTCSession_DTMF.C.MIN_DURATION} milliseconds');
      duration = RTCSession_DTMF.C.MIN_DURATION;
    } else if (duration > RTCSession_DTMF.C.MAX_DURATION) {
      logger.d(
          '"duration" value is greater than the maximum allowed, setting it to ${RTCSession_DTMF.C.MAX_DURATION} milliseconds');
      duration = RTCSession_DTMF.C.MAX_DURATION;
    } else {
      duration = duration.abs();
    }
    options['duration'] = duration;

    // Check interToneGap.
    if (interToneGap == null) {
      interToneGap = RTCSession_DTMF.C.DEFAULT_INTER_TONE_GAP;
    } else if (interToneGap < RTCSession_DTMF.C.MIN_INTER_TONE_GAP) {
      logger.d(
          '"interToneGap" value is lower than the minimum allowed, setting it to ${RTCSession_DTMF.C.MIN_INTER_TONE_GAP} milliseconds');
      interToneGap = RTCSession_DTMF.C.MIN_INTER_TONE_GAP;
    } else {
      interToneGap = interToneGap.abs();
    }

    options['interToneGap'] = interToneGap;

    //// ***************** and follows the actual code to queue DTMF tone(s) **********************

    ///using dtmfFuture to queue the playing of the tones

    for (int i = 0; i < tones.length; i++) {
      String tone = tones[i];
      if (tone == ',') {
        // queue the delay
        dtmfFuture = dtmfFuture.then((_) async {
          if (_state == RtcSessionState.terminated) {
            return;
          }
          await Future<void>.delayed(Duration(milliseconds: 2000), () {});
        });
      } else {
        // queue playing the tone
        dtmfFuture = dtmfFuture.then((_) async {
          if (_state == RtcSessionState.terminated) {
            return;
          }

          RTCSession_DTMF.DTMF dtmf = RTCSession_DTMF.DTMF(this, mode: mode);

          EventManager handlers = EventManager();
          handlers.on(EventCallFailed(), (EventCallFailed event) {
            logger.e('Failed to send DTMF ${event.cause}');
          });

          options!['eventHandlers'] = handlers;

          dtmf.send(tone, options);
          await Future<void>.delayed(
              Duration(milliseconds: sendInterval), () {});
        });
      }
    }
  }

  void sendInfo(String contentType, String body, Map<String, dynamic> options) {
    logger.d('sendInfo()');

    // Check Session Status.
    if (_state != RtcSessionState.confirmed &&
        _state != RtcSessionState.waitingForAck) {
      throw Exceptions.InvalidStateError(_state);
    }

    RTCSession_Info.Info info = RTCSession_Info.Info(this);

    info.send(contentType, body, options);
  }

  /**
   * Mute
   */
  void mute([bool audio = true, bool video = true]) {
    logger.d('mute()');
    bool changed = false;

    if (!_audioMuted && audio) {
      _audioMuted = true;
      changed = true;
    }
    if (!_videoMuted && video) {
      _videoMuted = true;
      changed = true;
    }

    if (changed) {
      _onmute(_audioMuted, _videoMuted);
    }
  }

  /**
   * Unmute
   */
  void unmute([bool audio = true, bool video = true]) {
    logger.d('unmute()');
    bool changed = false;

    if (_audioMuted == true && audio) {
      _audioMuted = false;

      if (_localHold == false) {
        changed = true;
        _toggleMuteAudio(false);
      }
    }

    if (_videoMuted == true && video) {
      _videoMuted = false;

      if (_localHold == false) {
        changed = true;
        _toggleMuteVideo(false);
      }
    }

    if (changed) {
      _onunmute(!_audioMuted, !_videoMuted);
    }
  }

  /**
   * Hold
   */
  bool hold([Map<String, dynamic>? options, Function(IncomingMessage?)? done]) {
    logger.d('hold()');

    options = options ?? <String, dynamic>{};

    if (_state != RtcSessionState.waitingForAck &&
        _state != RtcSessionState.confirmed) {
      return false;
    }

    if (_localHold == true) {
      return false;
    }

    if (!_isReadyToReOffer()) {
      return false;
    }

    _localHold = true;
    _onhold(Originator.local);

    EventManager handlers = EventManager();

    handlers.on(EventSucceeded(), (EventSucceeded event) {
      if (done != null) {
        done(event.response);
      }
    });
    handlers.on(EventCallFailed(), (EventCallFailed event) {
      terminate(<String, dynamic>{
        'cause': DartSIP_C.CausesType.WEBRTC_ERROR,
        'status_code': 500,
        'reason_phrase': 'Hold Failed'
      });
    });

    if (options['useUpdate'] != null) {
      _sendUpdate(<String, dynamic>{
        'sdpOffer': true,
        'eventHandlers': handlers,
        'extraHeaders': options['extraHeaders']
      });
    } else {
      _sendReinvite(<String, dynamic>{
        'eventHandlers': handlers,
        'extraHeaders': options['extraHeaders']
      });
    }

    return true;
  }

  bool unhold(
      [Map<String, dynamic>? options, Function(IncomingMessage?)? done]) {
    logger.d('unhold()');

    options = options ?? <String, dynamic>{};

    if (_state != RtcSessionState.waitingForAck &&
        _state != RtcSessionState.confirmed) {
      return false;
    }

    if (_localHold == false) {
      return false;
    }

    if (!_isReadyToReOffer()) {
      return false;
    }

    _localHold = false;
    _onunhold(Originator.local);

    EventManager handlers = EventManager();
    handlers.on(EventSucceeded(), (EventSucceeded event) {
      if (done != null) {
        done(event.response);
      }
    });
    handlers.on(EventCallFailed(), (EventCallFailed event) {
      terminate(<String, dynamic>{
        'cause': DartSIP_C.CausesType.WEBRTC_ERROR,
        'status_code': 500,
        'reason_phrase': 'Unhold Failed'
      });
    });

    if (options['useUpdate'] != null) {
      _sendUpdate(<String, dynamic>{
        'sdpOffer': true,
        'eventHandlers': handlers,
        'extraHeaders': options['extraHeaders']
      });
    } else {
      _sendReinvite(<String, dynamic>{
        'eventHandlers': handlers,
        'extraHeaders': options['extraHeaders']
      });
    }

    return true;
  }

  bool renegotiate(
      {Map<String, dynamic>? options,
      bool useUpdate = false,
      Function(IncomingMessage?)? done}) {
    logger.d('renegotiate()');

    options = options ?? <String, dynamic>{};
    EventManager handlers = options['eventHandlers'] ?? EventManager();

    Map<String, dynamic>? rtcOfferConstraints =
        options['rtcOfferConstraints'] ?? _rtcOfferConstraints;

    Map<String, dynamic> mediaConstraints =
        options['mediaConstraints'] ?? <String, dynamic>{};

    dynamic sdpSemantics =
        options['pcConfig']?['sdpSemantics'] ?? 'unified-plan';

    if (_state != RtcSessionState.waitingForAck &&
        _state != RtcSessionState.confirmed) {
      return false;
    }

    bool? upgradeToVideo;
    try {
      upgradeToVideo = (options['mediaConstraints']?['video'] != false ||
              options['mediaConstraints']?['mandatory']?['video'] != null) &&
          rtcOfferConstraints?['offerToReceiveVideo'] == null;
    } catch (e) {
      logger.w('Failed to determine upgrade to video: $e');
    }

    if (!_isReadyToReOffer()) {
      return false;
    }

    handlers.on(EventSucceeded(), (EventSucceeded event) {
      if (done != null && event.response != null) {
        done(event.response!);
      }
    });

    handlers.on(EventCallFailed(), (EventCallFailed event) {
      terminate(<String, dynamic>{
        'cause': DartSIP_C.CausesType.WEBRTC_ERROR,
        'status_code': 500,
        'reason_phrase': 'Media Renegotiation Failed'
      });
    });
    _setLocalMediaStatus();

    if (options['useUpdate'] != null) {
      _sendUpdate(<String, dynamic>{
        'sdpOffer': true,
        'eventHandlers': handlers,
        'rtcOfferConstraints': rtcOfferConstraints,
        'extraHeaders': options['extraHeaders']
      });
    } else {
      if (upgradeToVideo ?? false) {
        _sendVideoUpgradeReinvite(<String, dynamic>{
          'eventHandlers': handlers,
          'sdpSemantics': sdpSemantics,
          'rtcOfferConstraints': rtcOfferConstraints,
          'mediaConstraints': mediaConstraints,
          'extraHeaders': options['extraHeaders']
        });
      } else {
        _sendReinvite(<String, dynamic>{
          'eventHandlers': handlers,
          'rtcOfferConstraints': rtcOfferConstraints,
          'extraHeaders': options['extraHeaders']
        });
      }
    }

    return true;
  }

  /**
   * Refer
   */
  ReferSubscriber? refer(dynamic target, [Map<String, dynamic>? options]) {
    logger.d('refer()');

    options = options ?? <String, dynamic>{};

    dynamic originalTarget = target;

    if (_state != RtcSessionState.waitingForAck &&
        _state != RtcSessionState.confirmed) {
      return null;
    }

    // Check target validity.
    target = _ua.normalizeTarget(target);
    if (target == null) {
      throw Exceptions.TypeError('Invalid target: $originalTarget');
    }

    ReferSubscriber referSubscriber = ReferSubscriber(this);

    referSubscriber.sendRefer(target, options);

    // Store in the map.
    int? id = referSubscriber.id;

    _referSubscribers[id] = referSubscriber;

    // Listen for ending events so we can remove it from the map.
    referSubscriber.on(EventReferRequestFailed(),
        (EventReferRequestFailed data) {
      _referSubscribers.remove(id);
    });
    referSubscriber.on(EventReferAccepted(), (EventReferAccepted data) {
      _referSubscribers.remove(id);
    });
    referSubscriber.on(EventReferFailed(), (EventReferFailed data) {
      _referSubscribers.remove(id);
    });

    return referSubscriber;
  }

  /**
   * Send a generic in-dialog Request
   */
  OutgoingRequest sendRequest(SipMethod method,
      [Map<String, dynamic>? options]) {
    logger.d('sendRequest()');

    return _dialog!.sendRequest(method, options);
  }

  /**
   * In dialog Request Reception
   */
  void _receiveRequest(IncomingRequest request) async {
    logger.d('receiveRequest()');

    if (request.method == SipMethod.CANCEL) {
      /* RFC3261 15 States that a UAS may have accepted an invitation while a CANCEL
      * was in progress and that the UAC MAY continue with the session established by
      * any 2xx response, or MAY terminate with BYE. DartSIP does continue with the
      * established session. So the CANCEL is processed only if the session is not yet
      * established.
      */

      /*
      * Terminate the whole session in case the user didn't accept (or yet send the answer)
      * nor reject the request opening the session.
      */
      if (_state == RtcSessionState.waitingForAnswer ||
          _state == RtcSessionState.answered) {
        _state = RtcSessionState.canceled;
        _request.reply(487);
        _failed(Originator.remote, null, request, null, 487,
            DartSIP_C.CausesType.CANCELED, request.reason_phrase);
      }
    } else {
      // Requests arriving here are in-dialog requests.
      switch (request.method) {
        case SipMethod.ACK:
          if (_state != RtcSessionState.waitingForAck) {
            return;
          }
          // Update signaling status.
          _state = RtcSessionState.confirmed;
          clearTimeout(_timers.ackTimer);
          clearTimeout(_timers.invite2xxTimer);

          if (_late_sdp) {
            if (request.body == null) {
              terminate(<String, dynamic>{
                'cause': DartSIP_C.CausesType.MISSING_SDP,
                'status_code': 400
              });
              break;
            }

            logger.d('emit "sdp"');
            emit(EventSdp(
                originator: Originator.remote,
                type: SdpType.answer,
                sdp: request.body));

            RTCSessionDescription answer =
                RTCSessionDescription(request.body, SdpType.answer.name);
            try {
              await _connection!.setRemoteDescription(answer);
            } catch (error) {
              terminate(<String, dynamic>{
                'cause': DartSIP_C.CausesType.BAD_MEDIA_DESCRIPTION,
                'status_code': 488
              });
              logger.e(
                  'emit "peerconnection:setremotedescriptionfailed" [error:${error.toString()}]');
              emit(EventSetRemoteDescriptionFailed(exception: error));
            }
          }
          if (!_is_confirmed) {
            _confirmed(Originator.remote, request);
          }
          break;
        case SipMethod.BYE:
          if (_state == RtcSessionState.confirmed) {
            request.reply(200);
            _ended(
                Originator.remote,
                request,
                ErrorCause(
                    cause: DartSIP_C.CausesType.BYE,
                    status_code: 200,
                    reason_phrase: 'BYE Received'));
          } else if (_state == RtcSessionState.inviteReceived) {
            request.reply(200);
            _request.reply(487, 'BYE Received');
            _ended(
                Originator.remote,
                request,
                ErrorCause(
                    cause: DartSIP_C.CausesType.BYE,
                    status_code: request.status_code,
                    reason_phrase: request.reason_phrase));
          } else {
            request.reply(403, 'Wrong Status');
          }
          break;
        case SipMethod.INVITE:
          if (_state == RtcSessionState.confirmed) {
            if (request.hasHeader('replaces')) {
              _receiveReplaces(request);
            } else {
              _receiveReinvite(request);
            }
          } else {
            request.reply(403, 'Wrong Status');
          }
          break;
        case SipMethod.INFO:
          if (_state == RtcSessionState.provisionalResponse ||
              _state == RtcSessionState.waitingForAnswer ||
              _state == RtcSessionState.answered ||
              _state == RtcSessionState.waitingForAck ||
              _state == RtcSessionState.confirmed) {
            String? contentType = request.getHeader('content-type');
            if (contentType != null &&
                contentType.contains(RegExp(r'^application\/dtmf-relay',
                    caseSensitive: false))) {
              RTCSession_DTMF.DTMF(this).init_incoming(request);
            } else if (contentType != null) {
              RTCSession_Info.Info(this).init_incoming(request);
            } else {
              request.reply(415);
            }
          } else {
            request.reply(403, 'Wrong Status');
          }
          break;
        case SipMethod.UPDATE:
          if (_state == RtcSessionState.confirmed) {
            _receiveUpdate(request);
          } else {
            request.reply(403, 'Wrong Status');
          }
          break;
        case SipMethod.REFER:
          if (_state == RtcSessionState.confirmed) {
            _receiveRefer(request);
          } else {
            request.reply(403, 'Wrong Status');
          }
          break;
        case SipMethod.NOTIFY:
          if (_state == RtcSessionState.confirmed) {
            _receiveNotify(request);
          } else {
            request.reply(403, 'Wrong Status');
          }
          break;
        default:
          request.reply(501);
      }
    }
  }

  /**
   * Session Callbacks
   */
  void onTransportError() {
    logger.e('onTransportError()');
    if (_state != RtcSessionState.terminated) {
      terminate(<String, dynamic>{
        'status_code': 500,
        'reason_phrase': DartSIP_C.CausesType.CONNECTION_ERROR,
        'cause': DartSIP_C.CausesType.CONNECTION_ERROR
      });
    }
  }

  void onRequestTimeout() {
    logger.e('onRequestTimeout()');

    if (_state != RtcSessionState.terminated) {
      terminate(<String, dynamic>{
        'status_code': 408,
        'reason_phrase': DartSIP_C.CausesType.REQUEST_TIMEOUT,
        'cause': DartSIP_C.CausesType.REQUEST_TIMEOUT
      });
    }
  }

  void onDialogError() {
    logger.e('onDialogError()');

    if (_state != RtcSessionState.terminated) {
      terminate(<String, dynamic>{
        'status_code': 500,
        'reason_phrase': DartSIP_C.CausesType.DIALOG_ERROR,
        'cause': DartSIP_C.CausesType.DIALOG_ERROR
      });
    }
  }

  // Called from DTMF handler.
  void newDTMF(Originator originator, DTMF dtmf, dynamic request) {
    logger.d('newDTMF()');

    emit(EventNewDTMF(originator: originator, dtmf: dtmf, request: request));
  }

  // Called from Info handler.
  void newInfo(Originator originator, Info info, dynamic request) {
    logger.d('newInfo()');

    emit(EventNewInfo(originator: originator, info: info, request: request));
  }

  /**
   * Check if RTCSession is ready for an outgoing re-INVITE or UPDATE with SDP.
   */
  bool _isReadyToReOffer() {
    if (!_rtcReady) {
      logger.d('_isReadyToReOffer() | internal WebRTC status not ready');

      return false;
    }

    // No established yet.
    if (_dialog == null) {
      logger.d('_isReadyToReOffer() | session not established yet');

      return false;
    }

    // Another INVITE transaction is in progress.
    if (_dialog!.uac_pending_reply == true ||
        _dialog!.uas_pending_reply == true) {
      logger.d(
          '_isReadyToReOffer() | there is another INVITE/UPDATE transaction in progress');

      return false;
    }

    return true;
  }

  void _close() async {
    logger.d('close()');
    if (_state == RtcSessionState.terminated) {
      return;
    }
    _state = RtcSessionState.terminated;
    // Terminate RTC.
    if (_connection != null) {
      try {
        await _connection!.close();
        await _connection!.dispose();
        _connection = null;
      } catch (error) {
        logger.e(
            'close() | error closing the RTCPeerConnection: ${error.toString()}');
      }
    }
    // Close local MediaStream if it was not given by the user.
    if (_localMediaStream != null && _localMediaStreamLocallyGenerated) {
      logger.d('close() | closing local MediaStream');
      await _localMediaStream!.dispose();
      _localMediaStream = null;
    }

    // Terminate signaling.

    // Clear SIP timers.
    clearTimeout(_timers.ackTimer);
    clearTimeout(_timers.expiresTimer);
    clearTimeout(_timers.invite2xxTimer);
    clearTimeout(_timers.userNoAnswerTimer);

    _iceDisconnectTimer?.cancel();

    // Clear Session Timers.
    clearTimeout(_sessionTimers.timer);

    // Terminate confirmed dialog.
    if (_dialog != null) {
      _dialog!.terminate();
      _dialog = null;
    }

    // Terminate early dialogs.
    _earlyDialogs.forEach((String? key, _) {
      _earlyDialogs[key]!.terminate();
    });
    _earlyDialogs.clear();

    // Terminate REFER subscribers.
    _referSubscribers.clear();

    _ua.destroyRTCSession(this);
  }

  /**
   * Private API.
   */

  /**
   * RFC3261 13.3.1.4
   * Response retransmissions cannot be accomplished by transaction layer
   *  since it is destroyed when receiving the first 2xx answer
   */
  void _setInvite2xxTimer(dynamic request, String? body) {
    int timeout = Timers.T1;

    void invite2xxRetransmission() {
      if (_state != RtcSessionState.waitingForAck) {
        return;
      }
      request.reply(200, null, <String>['Contact: $_contact'], body);
      if (timeout < Timers.T2) {
        timeout = timeout * 2;
        if (timeout > Timers.T2) {
          timeout = Timers.T2;
        }
      }
      _timers.invite2xxTimer = setTimeout(invite2xxRetransmission, timeout);
    }

    _timers.invite2xxTimer = setTimeout(invite2xxRetransmission, timeout);
  }

  /**
   * RFC3261 14.2
   * If a UAS generates a 2xx response and never receives an ACK,
   *  it SHOULD generate a BYE to terminate the dialog.
   */
  void _setACKTimer() {
    _timers.ackTimer = setTimeout(() {
      if (_state == RtcSessionState.waitingForAck) {
        logger.d('no ACK received, terminating the session');

        clearTimeout(_timers.invite2xxTimer);
        sendRequest(SipMethod.BYE);
        _ended(
            Originator.remote,
            null,
            ErrorCause(
                cause: DartSIP_C.CausesType.NO_ACK,
                status_code: 408, // Request Timeout
                reason_phrase: 'no ACK received, terminating the session'));
      }
    }, Timers.TIMER_H);
  }

  void _iceRestart() async {
    Map<String, dynamic> offerConstraints = _rtcOfferConstraints ??
        <String, dynamic>{
          'mandatory': <String, dynamic>{},
          'optional': <dynamic>[],
        };
    offerConstraints['mandatory']['IceRestart'] = true;
    renegotiate(options: offerConstraints);
  }

  Future<void> _createRTCConnection(Map<String, dynamic> pcConfig,
      Map<String, dynamic> rtcConstraints) async {
    _connection = await createPeerConnection(pcConfig, rtcConstraints);
    _connection!.onIceConnectionState = (RTCIceConnectionState state) {
      if (_state == RtcSessionState.terminated ||
          _state == RtcSessionState.canceled) {
        logger.d(
            'ICE State change ignored, SIP session already terminated/canceled.');
        _iceDisconnectTimer?.cancel();
        return;
      }

      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        logger.e('ICE Connection State Failed.');
        _iceDisconnectTimer?.cancel();
        terminate(<String, dynamic>{
          'cause': DartSIP_C.CausesType.RTP_TIMEOUT,
          'status_code': 408,
          'reason_phrase': 'ICE Connection Failed'
        });
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        logger.w('ICE Connection State Disconnected.');
        if (_iceDisconnectTimer == null && !_isAttemptingIceRestart) {
          logger.i('Starting ICE disconnect timer...');
          _iceDisconnectTimer = Timer(const Duration(seconds: 20), () {
            logger.w('ICE disconnect timer fired!');
            if (_connection?.iceConnectionState ==
                    RTCIceConnectionState.RTCIceConnectionStateDisconnected &&
                _state != RtcSessionState.terminated &&
                _state != RtcSessionState.canceled &&
                !_isAttemptingIceRestart) {
              logger.i('Attempting ICE restart after timeout...');
              _isAttemptingIceRestart = true;
              _iceRestart();
            } else {
              logger.i('ICE restart aborted (state changed during timer).');
            }
            _iceDisconnectTimer = null;
          });
        } else {
          logger.d(
              'ICE disconnect timer not started (already running or attempting restart).');
        }
      } else if (state ==
              RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        // If connection recovers, cancel timer and reset flag
        if (_iceDisconnectTimer != null || _isAttemptingIceRestart) {
          logger.i(
              'ICE Connection State Connected/Completed. Canceling timer/resetting flag.');
          _iceDisconnectTimer?.cancel();
          _isAttemptingIceRestart = false;
        } else {
          logger.i('ICE Connection State Connected/Completed.');
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        // Connection closed locally, usually via _connection.close() called by terminate()
        logger.i('ICE Connection State Closed.'); // Use logger.i
        _iceDisconnectTimer?.cancel(); // Ensure timer is cancelled
        // Ensure *SIP* session state reflects closure if not already set by terminate()
        if (_state != RtcSessionState.terminated &&
            _state != RtcSessionState.canceled) {
          logger.w(
              'ICE closed but SIP session state was not terminal. Terminating SIP session now.');
          terminate(<String, dynamic>{
            'cause': DartSIP_C.CausesType.WEBRTC_ERROR,
            'status_code': 487,
            'reason_phrase': 'ICE Connection Closed'
          });
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
        logger.d('ICE Connection State Checking...'); // Use logger.d
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateNew) {
        logger.d('ICE Connection State New.'); // Use logger.d
      }
    };
    // In future versions, unified-plan will be used by default
    String? sdpSemantics = 'unified-plan';
    if (pcConfig['sdpSemantics'] != null) {
      sdpSemantics = pcConfig['sdpSemantics'];
    }

    switch (sdpSemantics) {
      case 'unified-plan':
        _connection!.onTrack = (RTCTrackEvent event) {
          if (event.streams.isNotEmpty) {
            emit(EventStream(
                session: this,
                originator: Originator.remote,
                stream: event.streams[0]));
          }
        };
        break;
      case 'plan-b':
        _connection!.onAddStream = (MediaStream stream) {
          emit(EventStream(
              session: this, originator: Originator.remote, stream: stream));
        };
        break;
    }

    logger.d('emit "peerconnection"');
    emit(EventPeerConnection(_connection));
    return;
  }

  Future<RTCSessionDescription> _createLocalDescription(
      SdpType type, Map<String, dynamic>? constraints) async {
    logger.d('createLocalDescription()');
    _iceGatheringState ??= RTCIceGatheringState.RTCIceGatheringStateNew;
    Completer<RTCSessionDescription> completer =
        Completer<RTCSessionDescription>();

    constraints = constraints ??
        <String, dynamic>{
          'mandatory': <String, dynamic>{},
          'optional': <dynamic>[],
        };

    List<Future<RTCSessionDescription> Function(RTCSessionDescription)>
        modifiers = constraints['offerModifiers'] ??
            <Future<RTCSessionDescription> Function(RTCSessionDescription)>[];

    constraints['offerModifiers'] = null;

    if (type != SdpType.offer && type != SdpType.answer) {
      completer.completeError(Exceptions.TypeError(
          'createLocalDescription() | invalid type "$type"'));
    }

    _rtcReady = false;
    late RTCSessionDescription desc;
    if (type == SdpType.offer) {
      try {
        desc = await _connection!.createOffer(constraints);
      } catch (error) {
        logger.e(
            'emit "peerconnection:createofferfailed" [error:${error.toString()}]');
        emit(EventCreateOfferFailed(exception: error));
        completer.completeError(error);
      }
    } else {
      try {
        desc = await _connection!.createAnswer(constraints);
      } catch (error) {
        logger.e(
            'emit "peerconnection:createanswerfailed" [error:${error.toString()}]');
        emit(EventCreateAnswerFialed(exception: error));
        completer.completeError(error);
      }
    }

    // Add 'pc.onicencandidate' event handler to resolve on last candidate.
    bool finished = false;

    for (Future<RTCSessionDescription> Function(RTCSessionDescription) modifier
        in modifiers) {
      desc = await modifier(desc);
    }

    Future<void> ready() async {
      if (!finished && _state != RtcSessionState.terminated) {
        finished = true;
        _connection!.onIceCandidate = null;
        _connection!.onIceGatheringState = null;
        _iceGatheringState = RTCIceGatheringState.RTCIceGatheringStateComplete;
        _rtcReady = true;
        RTCSessionDescription? desc = await _connection!.getLocalDescription();
        logger.d('emit "sdp"');
        emit(
            EventSdp(originator: Originator.local, type: type, sdp: desc!.sdp));
        completer.complete(desc);
      }
    }

    _connection!.onIceGatheringState = (RTCIceGatheringState state) {
      _iceGatheringState = state;
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        ready();
      }
    };

    bool hasCandidate = false;
    _connection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate != null) {
        emit(EventIceCandidate(candidate, ready));
        if (!hasCandidate) {
          hasCandidate = true;
          /**
           *  Just wait for 0.5 seconds. In the case of multiple network connections,
           *  the RTCIceGatheringStateComplete event needs to wait for 10 ~ 30 seconds.
           *  Because trickle ICE is not defined in the sip protocol, the delay of
           * initiating a call to answer the call waiting will be unacceptable.
           */
          if (ua.configuration.ice_gathering_timeout != 0) {
            setTimeout(() => ready(), ua.configuration.ice_gathering_timeout);
          }
        }
      }
    };

    try {
      await _connection!.setLocalDescription(desc);
    } catch (error) {
      _rtcReady = true;
      logger.e(
          'emit "peerconnection:setlocaldescriptionfailed" [error:${error.toString()}]');
      emit(EventSetLocalDescriptionFailed(exception: error));
      completer.completeError(error);
    }

    // Resolve right away if 'pc.iceGatheringState' is 'complete'.
    if (_iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      _rtcReady = true;
      RTCSessionDescription? desc = await _connection!.getLocalDescription();
      logger.d('emit "sdp"');
      emit(EventSdp(originator: Originator.local, type: type, sdp: desc!.sdp));
      return desc;
    }

    return completer.future;
  }

  /**
   * Dialog Management
   */
  bool _createDialog(dynamic message, String type, [bool early = false]) {
    String? local_tag = (type == 'UAS') ? message.to_tag : message.from_tag;
    String? remote_tag = (type == 'UAS') ? message.from_tag : message.to_tag;
    String? id = message.call_id + local_tag + remote_tag;
    Dialog? early_dialog = _earlyDialogs[id];

    // Early Dialog.
    if (early) {
      if (early_dialog != null) {
        return true;
      } else {
        try {
          early_dialog = Dialog(this, message, type, DialogStatus.STATUS_EARLY);
        } catch (error) {
          logger.d('$error');
          _failed(
              Originator.remote,
              message,
              null,
              null,
              500,
              DartSIP_C.CausesType.INTERNAL_ERROR,
              'Can\'t create Early Dialog');
          return false;
        }
        // Dialog has been successfully created.
        _earlyDialogs[id] = early_dialog;
        return true;
      }
    } else {
      // Confirmed Dialog.
      _from_tag = message.from_tag;
      _to_tag = message.to_tag;

      // In case the dialog is in _early_ state, update it.
      if (early_dialog != null) {
        early_dialog.update(message, type);
        _dialog = early_dialog;
        _earlyDialogs.remove(id);
        return true;
      }

      try {
        // Otherwise, create a _confirmed_ dialog.
        _dialog = Dialog(this, message, type);
        return true;
      } catch (error) {
        logger.d(error.toString());
        _failed(
            Originator.remote,
            message,
            null,
            null,
            500,
            DartSIP_C.CausesType.INTERNAL_ERROR,
            'Can\'t create Confirmed Dialog');
        return false;
      }
    }
  }

  /// In dialog INVITE Reception
  void _receiveReinvite(IncomingRequest request) async {
    logger.d('receiveReinvite()');
    String? contentType = request.getHeader('Content-Type');

    void sendAnswer(String? sdp) async {
      List<String> extraHeaders = <String>['Contact: $_contact'];

      _handleSessionTimersInIncomingRequest(request, extraHeaders);

      if (_late_sdp) {
        sdp = _mangleOffer(sdp);
      }

      request.reply(200, null, extraHeaders, sdp, () {
        _state = RtcSessionState.waitingForAck;
        _setInvite2xxTimer(request, sdp);
        _setACKTimer();
      });

      // If callback is given execute it.
      if (data!['callback'] is Function) {
        data!['callback']();
      }
    }

    _late_sdp = false;

    // Request without SDP.
    if (request.body == null) {
      _late_sdp = true;

      try {
        RTCSessionDescription desc =
            await _createLocalDescription(SdpType.offer, _rtcOfferConstraints);
        sendAnswer(desc.sdp);
      } catch (_) {
        request.reply(500);
      }
      return;
    }

    // Request without SDP.
    if (contentType != 'application/sdp') {
      logger.d('invalid Content-Type');
      request.reply(415);
      return;
    }

    bool reject(dynamic options) {
      int status_code = options['status_code'] ?? 403;
      String? reason_phrase = options['reason_phrase'];
      List<dynamic> extraHeaders = utils.cloneArray(options['extraHeaders']);

      if (_state != RtcSessionState.confirmed) {
        return false;
      }

      if (status_code < 300 || status_code >= 700) {
        throw Exceptions.TypeError('Invalid status_code: $status_code');
      }
      logger.i(
          'Rejecting with status code: $status_code, reason: $reason_phrase');
      request.reply(status_code, reason_phrase, extraHeaders);
      return true;
    }

    RTCSessionDescription? desc = await _processInDialogSdpOffer(request);

    Future<bool> acceptReInvite(dynamic options) async {
      try {
        // Send answer.
        if (_state == RtcSessionState.terminated) {
          return false;
        }
        sendAnswer(desc.sdp);
      } catch (error) {
        logger.e('Got anerror on re-INVITE: ${error.toString()}');
      }

      return true;
    }

    String body = request.body ?? '';
    bool hasAudio = false;
    bool hasVideo = false;
    if (request.sdp == null && body.isNotEmpty) {
      request.sdp = sdp_transform.parse(body);
    }
    List<dynamic> media = request.sdp?['media'];
    for (Map<String, dynamic> m in media) {
      if (m['type'] == 'audio') {
        hasAudio = true;
      } else if (m['type'] == 'video') {
        hasVideo = true;
      }
    }
    emit(EventReInvite(
        request: request,
        hasAudio: hasAudio,
        hasVideo: hasVideo,
        callback: acceptReInvite,
        reject: reject));
  }

  /**
   * In dialog UPDATE Reception
   */
  void _receiveUpdate(IncomingRequest request) async {
    logger.d('receiveUpdate()');

    bool rejected = false;

    bool reject(Map<String, dynamic> options) {
      rejected = true;

      int status_code = options['status_code'] ?? 403;
      String reason_phrase = options['reason_phrase'] ?? '';
      List<dynamic> extraHeaders = utils.cloneArray(options['extraHeaders']);

      if (_state != RtcSessionState.confirmed) {
        return false;
      }

      if (status_code < 300 || status_code >= 700) {
        throw Exceptions.TypeError('Invalid status_code: $status_code');
      }

      request.reply(status_code, reason_phrase, extraHeaders);
      return true;
    }

    String? contentType = request.getHeader('Content-Type');

    void sendAnswer(String? sdp) {
      List<String> extraHeaders = <String>['Contact: $_contact'];
      _handleSessionTimersInIncomingRequest(request, extraHeaders);
      request.reply(200, null, extraHeaders, sdp);
    }

    // Emit 'update'.
    emit(EventUpdate(request: request, callback: null, reject: reject));

    if (rejected) {
      return;
    }

    if (request.body == null || request.body!.isEmpty) {
      sendAnswer(null);
      return;
    }

    if (contentType != 'application/sdp') {
      logger.d('invalid Content-Type');

      request.reply(415);

      return;
    }

    try {
      RTCSessionDescription desc = await _processInDialogSdpOffer(request);
      if (_state == RtcSessionState.terminated) return;
      // Send answer.
      sendAnswer(desc.sdp);
    } catch (error) {
      logger.e('Got error on UPDATE: ${error.toString()}');
    }
  }

  Future<RTCSessionDescription> _processInDialogSdpOffer(
      IncomingRequest request) async {
    logger.d('_processInDialogSdpOffer()');

    Map<String, dynamic>? sdp = request.parseSDP();

    bool hold = false;
    bool upgradeToVideo = false;
    if (sdp != null) {
      List<dynamic> mediaList = sdp['media'];

      // Loop media list items for video upgrade
      for (Map<String, dynamic> media in mediaList) {
        if (holdMediaTypes.indexOf(media['type']) == -1) continue;
        if (media['type'] == 'video') upgradeToVideo = true;
      }
      // Loop media list items for hold
      for (Map<String, dynamic> media in mediaList) {
        if (holdMediaTypes.indexOf(media['type']) == -1) continue;
        String direction = media['direction'] ?? sdp['direction'] ?? 'sendrecv';
        if (direction == 'sendonly' || direction == 'inactive') {
          hold = true;
        }
        // If at least one of the streams is active don't emit 'hold'.
        else {
          hold = false;
        }
      }
    }

    if (upgradeToVideo) {
      Map<String, dynamic> mediaConstraints = <String, dynamic>{
        'audio': true,
        'video': <String, dynamic>{
          'mandatory': <String, dynamic>{
            'minWidth': '640',
            'minHeight': '480',
            'minFrameRate': '30',
          },
          'facingMode': 'user',
        }
      };
      bool hasCamera = false;
      try {
        List<MediaDeviceInfo> devices =
            await navigator.mediaDevices.enumerateDevices();
        for (MediaDeviceInfo device in devices) {
          if (device.kind == 'videoinput') hasCamera = true;
        }
      } catch (e) {
        logger.w('Failed to enumerate devices: $e');
      }
      if (hasCamera) {
        MediaStream localStream =
            await navigator.mediaDevices.getUserMedia(mediaConstraints);
        if (localStream.getVideoTracks().isEmpty) {
          logger.w(
              'Remote wants to upgrade to video but failed to get local video');
        }
        for (MediaStreamTrack track in localStream.getTracks()) {
          if (track.kind == 'video') {
            _connection!.addTrack(track, localStream);
            _localMediaStream?.addTrack(track);
          }
        }
        emit(EventStream(
            session: this,
            originator: Originator.local,
            stream: _localMediaStream));
      } else {
        logger.w(
            'Remote wants to upgrade to video but no camera available to send');
      }
    }

    logger.d('emit "sdp"');
    final String? processedSDP = _sdpOfferToWebRTC(request.body);
    emit(EventSdp(
        originator: Originator.remote, type: SdpType.offer, sdp: processedSDP));

    RTCSessionDescription offer =
        RTCSessionDescription(processedSDP, SdpType.offer.name);

    if (_state == RtcSessionState.terminated) {
      throw Exceptions.InvalidStateError('terminated');
    }
    try {
      await _connection!.setRemoteDescription(offer);
    } catch (error) {
      request.reply(488);
      logger.e(
          'emit "peerconnection:setremotedescriptionfailed" [error:${error.toString()}]');

      emit(EventSetRemoteDescriptionFailed(exception: error));

      throw Exceptions.TypeError(
          'peerconnection.setRemoteDescription() failed');
    }

    if (_state == RtcSessionState.terminated) {
      throw Exceptions.InvalidStateError('terminated');
    }

    if (_remoteHold == true && hold == false) {
      _remoteHold = false;
      _onunhold(Originator.remote);
    } else if (_remoteHold == false && hold == true) {
      _remoteHold = true;
      _onhold(Originator.remote);
    }

    // Create local description.

    if (_state == RtcSessionState.terminated) {
      throw Exceptions.InvalidStateError('terminated');
    }

    try {
      return await _createLocalDescription(
          SdpType.answer, _rtcAnswerConstraints);
    } catch (_) {
      request.reply(500);
      throw Exceptions.TypeError('_createLocalDescription() failed');
    }
  }

  /**
   * In dialog Refer Reception
   */
  void _receiveRefer(IncomingRequest request) {
    logger.d('receiveRefer()');

    if (request.refer_to == null) {
      logger.d('no Refer-To header field present in REFER');
      request.reply(400);

      return;
    }

    if (request.refer_to.uri.scheme != DartSIP_C.SIP) {
      logger.d('Refer-To header field points to a non-SIP URI scheme');
      request.reply(416);
      return;
    }

    // Reply before the transaction timer expires.
    request.reply(202);

    ReferNotifier notifier = ReferNotifier(this, request.cseq);

    bool accept2(
        InitSuccessCallback? initCallback, Map<String, dynamic> options) {
      initCallback = (initCallback is Function) ? initCallback : null;

      if (_state != RtcSessionState.waitingForAck &&
          _state != RtcSessionState.confirmed) {
        return false;
      }

      RTCSession session = RTCSession(_ua);

      session.on(EventCallProgress(), (EventCallProgress event) {
        notifier.notify(
            event.response.status_code, event.response.reason_phrase);
      });

      session.on(EventCallAccepted(), (EventCallAccepted event) {
        notifier.notify(
            event.response.status_code, event.response.reason_phrase);
      });

      session.on(EventFailedUnderScore(), (EventFailedUnderScore data) {
        if (data.cause != null) {
          notifier.notify(data.cause!.status_code, data.cause!.reason_phrase);
        } else {
          notifier.notify(487, data.cause!.cause);
        }
      });
      // Consider the Replaces header present in the Refer-To URI.
      if (request.refer_to.uri.hasHeader('replaces')) {
        String replaces = utils
            .decodeURIComponent(request.refer_to.uri.getHeader('replaces'));

        options['extraHeaders'] = utils.cloneArray(options['extraHeaders']);
        options['extraHeaders'].add('Replaces: $replaces');
      }
      session.connect(request.refer_to.uri.toAor(), options, initCallback);
      return true;
    }

    void reject() {
      notifier.notify(603);
    }

    logger.d('emit "refer"');

    // Emit 'refer'.
    emit(EventCallRefer(
        session: this,
        aor: request.refer_to.uri.toAor(),
        accept:
            (InitSuccessCallback initCallback, Map<String, dynamic> options) {
          accept2(initCallback, options);
        },
        reject: (_) {
          reject();
        }));
  }

  /**
   * In dialog Notify Reception
   */
  void _receiveNotify(IncomingRequest request) {
    logger.d('receiveNotify()');

    if (request.event == null) {
      request.reply(400);
    }

    switch (request.event!.event) {
      case 'refer':
        {
          int? id;
          ReferSubscriber? referSubscriber;

          if (request.event!.params!['id'] != null) {
            id = int.tryParse(request.event!.params!['id'], radix: 10);
            referSubscriber = _referSubscribers[id];
          } else if (_referSubscribers.length == 1) {
            referSubscriber =
                _referSubscribers[_referSubscribers.keys.toList()[0]];
          } else {
            request.reply(400, 'Missing event id parameter');

            return;
          }

          if (referSubscriber == null) {
            request.reply(481, 'Subscription does not exist');

            return;
          }

          referSubscriber.receiveNotify(request);
          request.reply(200);

          break;
        }

      default:
        {
          request.reply(489);
        }
    }
  }

  /**
   * INVITE with Replaces Reception
   */
  void _receiveReplaces(IncomingRequest request) {
    logger.d('receiveReplaces()');

    bool accept(InitSuccessCallback initCallback) {
      if (_state != RtcSessionState.waitingForAck &&
          _state != RtcSessionState.confirmed) {
        return false;
      }

      RTCSession session = RTCSession(_ua);

      // Terminate the current session when the one is confirmed.
      session.on(EventCallConfirmed(), (EventCallConfirmed data) {
        terminate();
      });

      session.init_incoming(request, initCallback);
      return true;
    }

    void reject() {
      logger.d('Replaced INVITE rejected by the user');
      request.reply(486);
    }

    // Emit 'replace'.
    emit(EventReplaces(
        request: request,
        accept: (InitSuccessCallback initCallback) {
          accept(initCallback);
        },
        reject: () {
          reject();
        }));
  }

  /**
   * Initial Request Sender
   */
  Future<void> _sendInitialRequest(
      Map<String, dynamic> pcConfig,
      Map<String, dynamic> mediaConstraints,
      Map<String, dynamic> rtcOfferConstraints,
      MediaStream? mediaStream) async {
    EventManager handlers = EventManager();
    handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout value) {
      onRequestTimeout();
    });
    handlers.on(EventOnTransportError(), (EventOnTransportError value) {
      onTransportError();
    });
    handlers.on(EventOnAuthenticated(), (EventOnAuthenticated event) {
      _request = event.request;
    });
    handlers.on(EventOnReceiveResponse(), (EventOnReceiveResponse event) {
      _receiveInviteResponse(event.response);
    });

    RequestSender request_sender = RequestSender(_ua, _request, handlers);

    // In future versions, unified-plan will be used by default
    String? sdpSemantics = 'unified-plan';
    if (pcConfig['sdpSemantics'] != null) {
      sdpSemantics = pcConfig['sdpSemantics'];
    }

    // This Promise is resolved within the next iteration, so the app has now
    // a chance to set events such as 'peerconnection' and 'connecting'.
    MediaStream? stream;
    // A stream is given, var the app set events such as 'peerconnection' and 'connecting'.
    if (mediaStream != null) {
      stream = mediaStream;
      emit(EventStream(
          session: this, originator: Originator.local, stream: stream));
    } // Request for user media access.
    else if (mediaConstraints['audio'] != null ||
        mediaConstraints['video'] != null) {
      _localMediaStreamLocallyGenerated = true;
      try {
        stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
        emit(EventStream(
            session: this, originator: Originator.local, stream: stream));
      } catch (error) {
        if (_state == RtcSessionState.terminated) {
          throw Exceptions.InvalidStateError('terminated');
        }
        _failed(
            Originator.local,
            null,
            null,
            null,
            500,
            DartSIP_C.CausesType.USER_DENIED_MEDIA_ACCESS,
            'User Denied Media Access');
        logger.e('emit "getusermediafailed" [error:${error.toString()}]');
        emit(EventGetUserMediaFailed(exception: error));
        rethrow;
      }
    }

    if (_state == RtcSessionState.terminated) {
      throw Exceptions.InvalidStateError('terminated');
    }

    _localMediaStream = stream;

    if (stream != null) {
      switch (sdpSemantics) {
        case 'unified-plan':
          stream.getTracks().forEach((MediaStreamTrack track) async {
            RTCRtpSender sender = await _connection!.addTrack(track, stream!);
            _senders.add(sender);
          });
          break;
        case 'plan-b':
          _connection!.addStream(stream);
          break;
        default:
          logger.e('Unkown sdp semantics $sdpSemantics');
          throw Exceptions.NotReadyError('Unkown sdp semantics $sdpSemantics');
      }
    }

    // TODO(cloudwebrtc): should this be triggered here?
    _connecting(_request);
    try {
      RTCSessionDescription desc =
          await _createLocalDescription(SdpType.offer, rtcOfferConstraints);
      if (_is_canceled || _state == RtcSessionState.terminated) {
        throw Exceptions.InvalidStateError('terminated');
      }

      _request.body = desc.sdp;
      _state = RtcSessionState.inviteSent;

      logger.d('emit "sending" [request]');

      // Emit 'sending' so the app can mangle the body before the request is sent.
      emit(EventSending(request: _request));

      request_sender.send();
    } catch (error, s) {
      logger.e(error.toString(), error: error, stackTrace: s);
      _failed(Originator.local, null, null, null, 500,
          DartSIP_C.CausesType.WEBRTC_ERROR, 'Can\'t create local SDP');
      if (_state == RtcSessionState.terminated) {
        return;
      }
      logger.e('Failed to _sendInitialRequest: ${error.toString()}');
      rethrow;
    }
  }

  /// Reception of Response for Initial INVITE
  void _receiveInviteResponse(IncomingResponse? response) async {
    logger.d('receiveInviteResponse()  current status: $_state ');

    if (response == null) {
      logger.d('No response received');
      return;
    }
    response.sdp = sdp_transform.parse(response.body ?? '');

    /// Handle 2XX retransmissions and responses from forked requests.
    if (_dialog != null &&
        (response.status_code >= 200 && response.status_code <= 299)) {
      ///
      /// If it is a retransmission from the endpoint that established
      /// the dialog, send an ACK
      ///
      if (_dialog!.id!.call_id == response.call_id &&
          _dialog!.id!.local_tag == response.from_tag &&
          _dialog!.id!.remote_tag == response.to_tag) {
        sendRequest(SipMethod.ACK);
        return;
      } else {
        // If not, send an ACK  and terminate.
        try {
          // ignore: unused_local_variable
          Dialog dialog = Dialog(this, response, 'UAC');
        } catch (error) {
          logger.d(error.toString());
          return;
        }
        sendRequest(SipMethod.ACK);
        sendRequest(SipMethod.BYE);
        return;
      }
    }

    // Proceed to cancellation if the user requested.
    if (_is_canceled) {
      if (response.status_code >= 100 && response.status_code < 200) {
        _request.cancel(_cancel_reason);
      } else if (response.status_code >= 200 && response.status_code < 299) {
        _acceptAndTerminate(response);
      }
      return;
    }

    if (_state != RtcSessionState.inviteSent &&
        _state != RtcSessionState.provisionalResponse) {
      return;
    }

    String status_code = response.status_code.toString();

    if (utils.test100(status_code)) {
      // 100 trying
      _state = RtcSessionState.provisionalResponse;
    } else if (utils.test1XX(status_code)) {
      // 1XX
      // Do nothing with 1xx responses without To tag.
      if (response.to_tag == null) {
        logger.d('1xx response received without to tag');
        return;
      }

      // Create Early Dialog if 1XX comes with contact.
      if (response.hasHeader('contact')) {
        // An error on dialog creation will fire 'failed' event.
        if (!_createDialog(response, 'UAC', true)) {
          return;
        }
      }

      _state = RtcSessionState.provisionalResponse;
      _progress(Originator.remote, response, int.parse(status_code));

      if (response.body == null || response.body!.isEmpty) {
        return;
      }

      logger.d('emit "sdp"');
      emit(EventSdp(
          originator: Originator.remote,
          type: SdpType.answer,
          sdp: response.body));

      RTCSessionDescription answer =
          RTCSessionDescription(response.body, SdpType.answer.name);

      try {
        await _connection!.setRemoteDescription(answer);
      } catch (error) {
        logger.e(
            'emit "peerconnection:setremotedescriptionfailed" [error:${error.toString()}]');
        emit(EventSetRemoteDescriptionFailed(exception: error));
      }
    } else if (utils.test2XX(status_code)) {
      // 2XX
      _state = RtcSessionState.confirmed;

      if (response.body == null || response.body!.isEmpty) {
        _acceptAndTerminate(response, 400, DartSIP_C.CausesType.MISSING_SDP);
        _failed(Originator.remote, null, null, response, 400,
            DartSIP_C.CausesType.BAD_MEDIA_DESCRIPTION, 'Missing SDP');
        return;
      }

      dynamic mediaPort = response.sdp?['media'][0]['port'] ?? 0;

      if (mediaPort == 0 && _ua.configuration.terminateOnAudioMediaPortZero) {
        _acceptAndTerminate(response, 400, DartSIP_C.CausesType.MISSING_SDP);
        _failed(Originator.remote, null, null, response, 400,
            DartSIP_C.CausesType.BAD_MEDIA_DESCRIPTION, 'Media port is zero');
        return;
      }

      // An error on dialog creation will fire 'failed' event.
      if (_createDialog(response, 'UAC') == null) {
        return;
      }

      logger.d('emit "sdp"');
      emit(EventSdp(
          originator: Originator.remote,
          type: SdpType.answer,
          sdp: response.body));

      RTCSessionDescription answer =
          RTCSessionDescription(response.body, SdpType.answer.name);

      // Be ready for 200 with SDP after a 180/183 with SDP.
      // We created a SDP 'answer' for it, so check the current signaling state.
      if (_connection!.signalingState ==
              RTCSignalingState.RTCSignalingStateStable ||
          _connection!.signalingState ==
              RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        try {
          RTCSessionDescription offer =
              await _connection!.createOffer(_rtcOfferConstraints!);
          await _connection!.setLocalDescription(offer);
        } catch (error) {
          _acceptAndTerminate(response, 500, error.toString());
          _failed(
              Originator.local,
              null,
              null,
              response,
              500,
              DartSIP_C.CausesType.WEBRTC_ERROR,
              'Can\'t create offer ${error.toString()}');
        }
      }

      try {
        await _connection!.setRemoteDescription(answer);
        // Handle Session Timers.
        _handleSessionTimersInIncomingResponse(response);
        _accepted(Originator.remote, response);
        OutgoingRequest ack = sendRequest(SipMethod.ACK);
        _confirmed(Originator.local, ack);
      } catch (error) {
        _acceptAndTerminate(response, 488, 'Not Acceptable Here');
        _failed(Originator.remote, null, null, response, 488,
            DartSIP_C.CausesType.BAD_MEDIA_DESCRIPTION, 'Not Acceptable Here');
        logger.e(
            'emit "peerconnection:setremotedescriptionfailed" [error:${error.toString()}]');
        emit(EventSetRemoteDescriptionFailed(exception: error));
      }
    } else {
      String cause = utils.sipErrorCause(response.status_code);
      _failed(Originator.remote, null, null, response, response.status_code,
          cause, response.reason_phrase);
    }
  }

  /**
   * Send Re-INVITE
   */
  void _sendReinvite([Map<String, dynamic>? options]) async {
    logger.d('sendReinvite()');

    options = options ?? <String, dynamic>{};

    List<dynamic> extraHeaders = options['extraHeaders'] != null
        ? utils.cloneArray(options['extraHeaders'])
        : <dynamic>[];
    EventManager eventHandlers = options['eventHandlers'] ?? EventManager();
    Map<String, dynamic>? rtcOfferConstraints =
        options['rtcOfferConstraints'] ?? _rtcOfferConstraints;

    bool succeeded = false;

    extraHeaders.add('Contact: $_contact');
    extraHeaders.add('Content-Type: application/sdp');

    // Session Timers.
    if (_sessionTimers.running) {
      extraHeaders.add(
          'Session-Expires: ${_sessionTimers.currentExpires};refresher=${_sessionTimers.refresher ? 'uac' : 'uas'}');
    }

    void onFailed([dynamic response]) {
      eventHandlers.emit(EventCallFailed(session: this, response: response));
    }

    void onSucceeded(IncomingResponse? response) async {
      if (_state == RtcSessionState.terminated) {
        return;
      }

      sendRequest(SipMethod.ACK);

      // If it is a 2XX retransmission exit now.
      if (succeeded != null) {
        return;
      }

      // Handle Session Timers.
      _handleSessionTimersInIncomingResponse(response);

      // Must have SDP answer.
      if (response!.body == null || response.body!.isEmpty) {
        onFailed();
        return;
      } else if (response.getHeader('Content-Type') != 'application/sdp') {
        onFailed();
        return;
      }

      logger.d('emit "sdp"');
      emit(EventSdp(
        originator: Originator.remote,
        type: SdpType.answer,
        sdp: response.body,
      ));

      RTCSessionDescription answer =
          RTCSessionDescription(response.body, SdpType.answer.name);

      try {
        await _connection!.setRemoteDescription(answer);
        eventHandlers.emit(EventSucceeded(response: response));
      } catch (error) {
        onFailed();
        logger.e(
            'emit "peerconnection:setremotedescriptionfailed" [error:${error.toString()}]');
        emit(EventSetRemoteDescriptionFailed(exception: error));
      }
    }

    try {
      RTCSessionDescription desc =
          await _createLocalDescription(SdpType.offer, rtcOfferConstraints);
      String? sdp = _mangleOffer(desc.sdp);
      logger.d('emit "sdp"');
      emit(EventSdp(
          originator: Originator.local, type: SdpType.offer, sdp: sdp));

      EventManager handlers = EventManager();
      handlers.on(EventOnSuccessResponse(), (EventOnSuccessResponse event) {
        onSucceeded(event.response as IncomingResponse?);
        succeeded = true;
      });
      handlers.on(EventOnErrorResponse(), (EventOnErrorResponse event) {
        onFailed(event.response);
      });
      handlers.on(EventOnTransportError(), (EventOnTransportError event) {
        onTransportError(); // Do nothing because session ends.
      });
      handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout event) {
        onRequestTimeout(); // Do nothing because session ends.
      });
      handlers.on(EventOnDialogError(), (EventOnDialogError event) {
        onDialogError(); // Do nothing because session ends.
      });

      sendRequest(SipMethod.INVITE, <String, dynamic>{
        'extraHeaders': extraHeaders,
        'body': sdp,
        'eventHandlers': handlers
      });
    } catch (e, s) {
      logger.e(e.toString(), error: e, stackTrace: s);
      onFailed();
    }
  }

  /**
   * Send Re-INVITE
   */
  void _sendVideoUpgradeReinvite([Map<String, dynamic>? options]) async {
    logger.d('sendVideoUpgradeReinvite()');

    options = options ?? <String, dynamic>{};

    List<dynamic> extraHeaders = options['extraHeaders'] != null
        ? utils.cloneArray(options['extraHeaders'])
        : <dynamic>[];
    EventManager eventHandlers = options['eventHandlers'] ?? EventManager();
    Map<String, dynamic>? rtcOfferConstraints =
        options['rtcOfferConstraints'] ?? _rtcOfferConstraints;

    Map<String, dynamic> mediaConstraints =
        options['mediaConstraints'] ?? <String, dynamic>{};

    mediaConstraints['audio'] = false;

    dynamic sdpSemantics =
        options['pcConfig']?['sdpSemantics'] ?? 'unified-plan';

    try {
      MediaStream localStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localMediaStreamLocallyGenerated = true;

      switch (sdpSemantics) {
        case 'unified-plan':
          localStream.getTracks().forEach((MediaStreamTrack track) {
            if (track.kind == 'video')
              _connection!.addTrack(track, localStream);
            _localMediaStream?.addTrack(track);
          });
          break;
        case 'plan-b':
          _connection!.addStream(localStream);
          break;
        default:
          logger.e('Unkown sdp semantics $sdpSemantics');
          throw Exceptions.NotReadyError('Unkown sdp semantics $sdpSemantics');
      }

      emit(EventStream(
          session: this,
          originator: Originator.local,
          stream: _localMediaStream));
    } catch (error) {
      if (_state == RtcSessionState.terminated) {
        throw Exceptions.InvalidStateError('terminated');
      }
      request.reply(480);
      _failed(
          Originator.local,
          null,
          null,
          null,
          480,
          DartSIP_C.CausesType.USER_DENIED_MEDIA_ACCESS,
          'User Denied Media Access');
      logger.e('emit "getusermediafailed" [error:${error.toString()}]');
      emit(EventGetUserMediaFailed(exception: error));
      throw Exceptions.InvalidStateError('getUserMedia() failed');
    }

    bool succeeded = false;

    extraHeaders.add('Contact: $_contact');
    extraHeaders.add('Content-Type: application/sdp');

    // Session Timers.
    if (_sessionTimers.running) {
      extraHeaders.add(
          'Session-Expires: ${_sessionTimers.currentExpires};refresher=${_sessionTimers.refresher ? 'uac' : 'uas'}');
    }

    void onFailed([dynamic response]) {
      eventHandlers.emit(EventCallFailed(session: this, response: response));
    }

    void onSucceeded(IncomingResponse? response) async {
      if (_state == RtcSessionState.terminated) {
        return;
      }

      sendRequest(SipMethod.ACK);

      // If it is a 2XX retransmission exit now.
      if (succeeded) {
        return;
      }

      // Handle Session Timers.
      _handleSessionTimersInIncomingResponse(response);

      // Must have SDP answer.
      if (response!.body == null || response.body!.isEmpty) {
        onFailed();
        return;
      } else if (response.getHeader('Content-Type') != 'application/sdp') {
        onFailed();
        return;
      }

      logger.d('emit "sdp"');
      emit(EventSdp(
          originator: Originator.remote,
          type: SdpType.answer,
          sdp: response.body));

      RTCSessionDescription answer =
          RTCSessionDescription(response.body, SdpType.answer.name);

      try {
        await _connection!.setRemoteDescription(answer);
        eventHandlers.emit(EventSucceeded(response: response));
      } catch (error) {
        onFailed();
        logger.e(
            'emit "peerconnection:setremotedescriptionfailed" [error:${error.toString()}]');
        emit(EventSetRemoteDescriptionFailed(exception: error));
      }
    }

    try {
      RTCSessionDescription desc =
          await _createLocalDescription(SdpType.offer, rtcOfferConstraints);
      String? sdp = _mangleOffer(desc.sdp);
      logger.d('emit "sdp"');
      emit(EventSdp(
          originator: Originator.local, type: SdpType.offer, sdp: sdp));

      EventManager handlers = EventManager();
      handlers.on(EventOnSuccessResponse(), (EventOnSuccessResponse event) {
        onSucceeded(event.response as IncomingResponse?);
        succeeded = true;
      });
      handlers.on(EventOnErrorResponse(), (EventOnErrorResponse event) {
        onFailed(event.response);
      });
      handlers.on(EventOnTransportError(), (EventOnTransportError event) {
        onTransportError(); // Do nothing because session ends.
      });
      handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout event) {
        onRequestTimeout(); // Do nothing because session ends.
      });
      handlers.on(EventOnDialogError(), (EventOnDialogError event) {
        onDialogError(); // Do nothing because session ends.
      });

      sendRequest(SipMethod.INVITE, <String, dynamic>{
        'extraHeaders': extraHeaders,
        'body': sdp,
        'eventHandlers': handlers
      });
    } catch (e, s) {
      logger.e(e.toString(), error: e, stackTrace: s);
      onFailed();
    }
  }

  /**
   * Send UPDATE
   */
  void _sendUpdate([Map<String, dynamic>? options]) async {
    logger.d('sendUpdate()');

    options = options ?? <String, dynamic>{};

    List<dynamic> extraHeaders =
        utils.cloneArray(options['extraHeaders'] ?? <dynamic>[]);
    EventManager eventHandlers = options['eventHandlers'] ?? EventManager();
    Map<String, dynamic> rtcOfferConstraints = options['rtcOfferConstraints'] ??
        _rtcOfferConstraints ??
        <String, dynamic>{};
    bool sdpOffer = options['sdpOffer'] ?? false;

    bool succeeded = false;

    extraHeaders.add('Contact: $_contact');

    // Session Timers.
    if (_sessionTimers.running) {
      extraHeaders.add(
          'Session-Expires: ${_sessionTimers.currentExpires};refresher=${_sessionTimers.refresher ? 'uac' : 'uas'}');
    }

    void onFailed([dynamic response]) {
      eventHandlers.emit(EventCallFailed(session: this, response: response));
    }

    void onSucceeded(IncomingResponse? response) async {
      if (_state == RtcSessionState.terminated) {
        return;
      }

      // Handle Session Timers.
      _handleSessionTimersInIncomingResponse(response);

      // If it is a 2XX retransmission exit now.
      if (succeeded != null) {
        return;
      }

      // Must have SDP answer.
      if (sdpOffer) {
        if (response!.body != null && response.body!.trim().isNotEmpty) {
          onFailed();
          return;
        } else if (response.getHeader('Content-Type') != 'application/sdp') {
          onFailed();
          return;
        }

        logger.d('emit "sdp"');
        emit(EventSdp(
            originator: Originator.remote,
            type: SdpType.answer,
            sdp: response.body));

        RTCSessionDescription answer =
            RTCSessionDescription(response.body, SdpType.answer.name);

        try {
          await _connection!.setRemoteDescription(answer);
          eventHandlers.emit(EventSucceeded(response: response));
        } catch (error) {
          onFailed(error);
          logger.e(
              'emit "peerconnection:setremotedescriptionfailed" [error:${error.toString()}]');
          emit(EventSetRemoteDescriptionFailed(exception: error));
        }
      }
      // No SDP answer.
      else {
        eventHandlers.emit(EventSucceeded(response: response));
      }
    }

    if (sdpOffer) {
      extraHeaders.add('Content-Type: application/sdp');
      try {
        RTCSessionDescription desc =
            await _createLocalDescription(SdpType.offer, rtcOfferConstraints);
        String? sdp = _mangleOffer(desc.sdp);

        logger.d('emit "sdp"');
        emit(EventSdp(
            originator: Originator.local, type: SdpType.offer, sdp: sdp));

        EventManager handlers = EventManager();
        handlers.on(EventOnSuccessResponse(), (EventOnSuccessResponse event) {
          onSucceeded(event.response as IncomingResponse?);
          succeeded = true;
        });
        handlers.on(EventOnErrorResponse(), (EventOnErrorResponse event) {
          onFailed(event.response);
        });
        handlers.on(EventOnTransportError(), (EventOnTransportError event) {
          onTransportError(); // Do nothing because session ends.
        });
        handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout event) {
          onRequestTimeout(); // Do nothing because session ends.
        });
        handlers.on(EventOnDialogError(), (EventOnDialogError event) {
          onDialogError(); // Do nothing because session ends.
        });

        sendRequest(SipMethod.UPDATE, <String, dynamic>{
          'extraHeaders': extraHeaders,
          'body': sdp,
          'eventHandlers': handlers
        });
      } catch (error) {
        onFailed(error);
      }
    } else {
      // No SDP.

      EventManager handlers = EventManager();
      handlers.on(EventOnSuccessResponse(), (EventOnSuccessResponse event) {
        onSucceeded(event.response as IncomingResponse?);
      });
      handlers.on(EventOnErrorResponse(), (EventOnErrorResponse event) {
        onFailed(event.response);
      });
      handlers.on(EventOnTransportError(), (EventOnTransportError event) {
        onTransportError(); // Do nothing because session ends.
      });
      handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout event) {
        onRequestTimeout(); // Do nothing because session ends.
      });
      handlers.on(EventOnDialogError(), (EventOnDialogError event) {
        onDialogError(); // Do nothing because session ends.
      });

      sendRequest(SipMethod.UPDATE, <String, dynamic>{
        'extraHeaders': extraHeaders,
        'eventHandlers': handlers
      });
    }
  }

  void _acceptAndTerminate(IncomingResponse? response,
      [int? status_code, String? reason_phrase]) async {
    logger.d(
        'acceptAndTerminate() status_code: $status_code reason: $reason_phrase');

    List<dynamic> extraHeaders = <dynamic>[];

    if (status_code != null) {
      reason_phrase =
          reason_phrase ?? DartSIP_C.REASON_PHRASE[status_code] ?? '';
      extraHeaders
          .add('Reason: SIP ;cause=$status_code; text="$reason_phrase"');
    }

    // An error on dialog creation will fire 'failed' event.
    if (_dialog != null || _createDialog(response, 'UAC')) {
      sendRequest(SipMethod.ACK);
      sendRequest(
          SipMethod.BYE, <String, dynamic>{'extraHeaders': extraHeaders});
    }

    // Update session status.
    _state = RtcSessionState.terminated;
  }

  /**
   * Correctly set the SDP direction attributes if the call is on local hold
   */
  String? _mangleOffer(String? sdpInput) {
    if (!_localHold && !_remoteHold) {
      return sdpInput;
    }

    Map<String, dynamic> sdp = sdp_transform.parse(sdpInput!);

    // Local hold.
    if (_localHold && !_remoteHold) {
      logger.d('mangleOffer() | me on hold, mangling offer');
      for (Map<String, dynamic> m in sdp['media']) {
        if (holdMediaTypes.indexOf(m['type']) == -1) {
          continue;
        }
        if (m['direction'] == null) {
          m['direction'] = 'sendonly';
        } else if (m['direction'] == 'sendrecv') {
          m['direction'] = 'sendonly';
        } else if (m['direction'] == 'recvonly') {
          m['direction'] = 'inactive';
        }
      }
    }
    // Local and remote hold.
    else if (_localHold && _remoteHold) {
      logger.d('mangleOffer() | both on hold, mangling offer');
      for (Map<String, dynamic> m in sdp['media']) {
        if (holdMediaTypes.indexOf(m['type']) == -1) {
          continue;
        }
        m['direction'] = 'inactive';
      }
    }
    // Remote hold.
    else if (_remoteHold) {
      logger.d('mangleOffer() | remote on hold, mangling offer');
      for (Map<String, dynamic> m in sdp['media']) {
        if (holdMediaTypes.indexOf(m['type']) == -1) {
          continue;
        }
        if (m['direction'] == null) {
          m['direction'] = 'recvonly';
        } else if (m['direction'] == 'sendrecv') {
          m['direction'] = 'recvonly';
        } else if (m['direction'] == 'recvonly') {
          m['direction'] = 'inactive';
        }
      }
    }

    return sdp_transform.write(sdp, null);
  }

  /// SDP offers may contain text media channels. e.g. Older clients using linphone.
  ///
  /// WebRTC does not support text media channels, so remove them.
  String? _sdpOfferToWebRTC(String? sdpInput) {
    if (sdpInput == null) {
      return sdpInput;
    }

    Map<String, dynamic> sdp = sdp_transform.parse(sdpInput);

    final List<Map<String, dynamic>> mediaList = <Map<String, dynamic>>[];

    for (dynamic element in sdp['media']) {
      if (element['type'] != 'text') {
        mediaList.add(element);
      }
    }
    sdp['media'] = mediaList;

    return sdp_transform.write(sdp, null);
  }

  void _setLocalMediaStatus() {
    bool enableAudio = true, enableVideo = true;
    if (_localHold || _remoteHold) {
      enableAudio = false;
      enableVideo = false;
    }
    if (_audioMuted) {
      enableAudio = false;
    }
    if (_videoMuted) {
      enableVideo = false;
    }
    _toggleMuteAudio(!enableAudio);
    _toggleMuteVideo(!enableVideo);
  }

  /**
   * Handle SessionTimers for an incoming INVITE or UPDATE.
   * @param  {IncomingRequest} request
   * @param  {Array} responseExtraHeaders  Extra headers for the 200 response.
   */
  void _handleSessionTimersInIncomingRequest(
      IncomingRequest request, List<dynamic> responseExtraHeaders) {
    if (!_sessionTimers.enabled) {
      return;
    }

    String session_expires_refresher;

    if (request.session_expires != null &&
        request.session_expires! > 0 &&
        request.session_expires! >= DartSIP_C.MIN_SESSION_EXPIRES) {
      _sessionTimers.currentExpires = request.session_expires;
      session_expires_refresher = request.session_expires_refresher ?? 'uas';
    } else {
      _sessionTimers.currentExpires = _sessionTimers.defaultExpires;
      session_expires_refresher = 'uas';
    }

    responseExtraHeaders.add(
        'Session-Expires: ${_sessionTimers.currentExpires};refresher=$session_expires_refresher');

    _sessionTimers.refresher = session_expires_refresher == 'uas';
    _runSessionTimer();
  }

  /**
   * Handle SessionTimers for an incoming response to INVITE or UPDATE.
   * @param  {IncomingResponse} response
   */
  void _handleSessionTimersInIncomingResponse(dynamic response) {
    if (!_sessionTimers.enabled) {
      return;
    }

    String session_expires_refresher;

    if (response.session_expires != null &&
        response.session_expires != 0 &&
        response.session_expires >= DartSIP_C.MIN_SESSION_EXPIRES) {
      _sessionTimers.currentExpires = response.session_expires;
      session_expires_refresher = response.session_expires_refresher ?? 'uac';
    } else {
      _sessionTimers.currentExpires = _sessionTimers.defaultExpires;
      session_expires_refresher = 'uac';
    }

    _sessionTimers.refresher = session_expires_refresher == 'uac';
    _runSessionTimer();
  }

  void _runSessionTimer() {
    int? expires = _sessionTimers.currentExpires;

    _sessionTimers.running = true;

    clearTimeout(_sessionTimers.timer);

    // I'm the refresher.
    if (_sessionTimers.refresher) {
      _sessionTimers.timer = setTimeout(() {
        if (_state == RtcSessionState.terminated) {
          return;
        }

        logger.d('runSessionTimer() | sending session refresh request');

        if (_sessionTimers.refreshMethod == SipMethod.UPDATE) {
          _sendUpdate();
        } else {
          _sendReinvite();
        }
      }, expires! * 500); // Half the given interval (as the RFC states).
    }
    // I'm not the refresher.
    else {
      _sessionTimers.timer = setTimeout(() {
        if (_state == RtcSessionState.terminated) {
          return;
        }

        logger.e('runSessionTimer() | timer expired, terminating the session');

        terminate(<String, dynamic>{
          'cause': DartSIP_C.CausesType.REQUEST_TIMEOUT,
          'status_code': 408,
          'reason_phrase': 'Session Timer Expired'
        });
      }, expires! * 1100);
    }
  }

  void _toggleMuteAudio(bool mute) {
    if (_localMediaStream != null) {
      if (_localMediaStream!.getAudioTracks().isEmpty) {
        logger.w('Went to mute video but local stream has no video tracks');
      }
      for (MediaStreamTrack track in _localMediaStream!.getAudioTracks()) {
        track.enabled = !mute;
      }
    } else {
      logger.w('Went to mute audio but local stream is null');
    }
  }

  void _toggleMuteVideo(bool mute) {
    if (_localMediaStream != null) {
      if (_localMediaStream!.getVideoTracks().isEmpty) {
        logger.w(
            'Went to toggle mute video but local stream has no video tracks');
      }
      for (MediaStreamTrack track in _localMediaStream!.getVideoTracks()) {
        track.enabled = !mute;
      }
    } else {
      logger.w('Went to mute video but local stream is null');
    }
  }

  void _newRTCSession(Originator originator, dynamic request) {
    logger.d('newRTCSession()');
    _ua.newRTCSession(originator: originator, session: this, request: request);
  }

  void _connecting(dynamic request) {
    logger.d('session connecting');
    logger.d('emit "connecting"');
    emit(EventCallConnecting(session: this, request: request));
  }

  void _progress(Originator originator, dynamic response, [int? status_code]) {
    logger.d('session progress');
    logger.d('emit "progress"');

    ErrorCause errorCause = ErrorCause(status_code: status_code);

    emit(EventCallProgress(
        session: this,
        originator: originator,
        response: response,
        cause: errorCause));
  }

  void _accepted(Originator originator, [dynamic message]) {
    logger.d('session accepted');
    _start_time = DateTime.now();
    logger.d('emit "accepted"');
    emit(EventCallAccepted(
        session: this, originator: originator, response: message));
  }

  void _confirmed(Originator originator, dynamic ack) {
    logger.d('session confirmed');
    _is_confirmed = true;
    logger.d('emit "confirmed"');
    emit(EventCallConfirmed(session: this, originator: originator, ack: ack));
  }

  void _ended(
      Originator originator, IncomingRequest? request, ErrorCause cause) {
    logger.d('session ended');
    _end_time = DateTime.now();
    _close();
    logger.d('emit "ended"');
    emit(EventCallEnded(
        session: this, originator: originator, request: request, cause: cause));
  }

  void _failed(Originator originator, dynamic message, dynamic request,
      dynamic response, int? status_code, String cause, String? reason_phrase) {
    logger.d('session failed');

    // Emit private '_failed' event first.
    logger.d('emit "_failed"');

    ErrorCause errorCause = ErrorCause(
        cause: cause, status_code: status_code, reason_phrase: reason_phrase);

    emit(EventFailedUnderScore(
      originator: originator,
      cause: errorCause,
    ));

    _close();
    logger.d('emit "failed"');
    emit(EventCallFailed(
        session: this,
        originator: originator,
        request: request,
        cause: errorCause,
        response: response));
  }

  void _onhold(Originator originator) {
    logger.d('session onhold');
    _setLocalMediaStatus();
    logger.d('emit "hold"');
    emit(EventCallHold(session: this, originator: originator));
  }

  void _onunhold(Originator originator) {
    logger.d('session onunhold');
    _setLocalMediaStatus();
    logger.d('emit "unhold"');
    emit(EventCallUnhold(session: this, originator: originator));
  }

  void _onmute([bool? audio, bool? video]) {
    logger.d('session onmute');
    _setLocalMediaStatus();
    logger.d('emit "muted"');
    emit(EventCallMuted(session: this, audio: audio, video: video));
  }

  void _onunmute([bool? audio, bool? video]) {
    logger.d('session onunmute');
    _setLocalMediaStatus();
    logger.d('emit "unmuted"');
    emit(EventCallUnmuted(session: this, audio: audio, video: video));
  }
}
