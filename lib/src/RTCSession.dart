import 'dart:async';

import 'package:events2/events2.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:sdp_transform/sdp_transform.dart' as sdp_transform;

import '../sip_ua.dart';
import 'Constants.dart';
import 'Constants.dart' as DartSIP_C;
import 'Dialog.dart';
import 'Exceptions.dart' as Exceptions;
import 'NameAddrHeader.dart';
import 'RTCSession/DTMF.dart' as RTCSession_DTMF;
import 'RTCSession/Info.dart' as RTCSession_Info;
import 'RTCSession/ReferNotifier.dart' as RTCSession_ReferNotifier;
import 'RTCSession/ReferSubscriber.dart' as RTCSession_ReferSubscriber;
import 'RequestSender.dart';
import 'SIPMessage.dart';
import 'SIPMessage.dart' as SIPMessage;
import 'Timers.dart';
import 'URI.dart';
import 'Utils.dart' as Utils;
import 'logger.dart';
import 'transactions/transaction_base.dart';

class C {
  // RTCSession states.
  static const STATUS_NULL = 0;
  static const STATUS_INVITE_SENT = 1;
  static const STATUS_1XX_RECEIVED = 2;
  static const STATUS_INVITE_RECEIVED = 3;
  static const STATUS_WAITING_FOR_ANSWER = 4;
  static const STATUS_ANSWERED = 5;
  static const STATUS_WAITING_FOR_ACK = 6;
  static const STATUS_CANCELED = 7;
  static const STATUS_TERMINATED = 8;
  static const STATUS_CONFIRMED = 9;
}

/**
 * Local variables.
 */
const holdMediaTypes = ['audio', 'video'];

class SIPTimers {
  Timer ackTimer;
  Timer expiresTimer;
  Timer invite2xxTimer;
  Timer userNoAnswerTimer;
}

class RFC4028Timers {
  bool enabled;
  SipMethod refreshMethod;
  int defaultExpires;
  int currentExpires;
  bool running;
  bool refresher;
  Timer timer;
  RFC4028Timers(this.enabled, this.refreshMethod, this.defaultExpires,
      this.currentExpires, this.running, this.refresher, this.timer);
}

class RTCSession extends EventEmitter {
  var _id;
  UA _ua;
  var _request;
  bool _late_sdp;
  var _rtcOfferConstraints;
  MediaStream _localMediaStream;
  var _data;
  Map<String, Dialog> _earlyDialogs;
  String _from_tag;
  var _to_tag;
  var _rtcAnswerConstraints;
  SIPTimers _timers;
  bool _is_confirmed;
  bool _is_canceled;
  RFC4028Timers _sessionTimers;
  var _cancel_reason;
  var _status;
  Dialog _dialog;
  RTCPeerConnection _connection;
  var _iceGatheringState;
  bool _localMediaStreamLocallyGenerated;
  bool _rtcReady;
  String _direction;

  Map _referSubscribers;
  var _start_time;
  var _end_time;

  bool _audioMuted;
  bool _videoMuted;
  bool _localHold;
  bool _remoteHold;

  NameAddrHeader _local_identity;
  NameAddrHeader _remote_identity;

  String _contact;
  var _tones;
  var _sendDTMF;
  final logger = new Logger('RTCSession');

  debug(msg) => logger.debug(msg);
  debugerror(error) => logger.error(error);

  Function(IncomingRequest) receiveRequest;

  RTCSession(UA ua) {
    debug('new');

    this._id = null;
    this._ua = ua;
    this._status = C.STATUS_NULL;
    this._dialog = null;
    this._earlyDialogs = {};
    this._contact = null;
    this._from_tag = null;
    this._to_tag = null;

    // The RTCPeerConnection instance (public attribute).
    this._connection = null;

    // Incoming/Outgoing request being currently processed.
    this._request = null;

    // Cancel state for initial outgoing request.
    this._is_canceled = false;
    this._cancel_reason = '';

    // RTCSession confirmation flag.
    this._is_confirmed = false;

    // Is late SDP being negotiated.
    this._late_sdp = false;

    // Default rtcOfferConstraints and rtcAnswerConstrainsts (passed in connect() or answer()).
    this._rtcOfferConstraints = null;
    this._rtcAnswerConstraints = null;

    // Local MediaStream.
    this._localMediaStream = null;
    this._localMediaStreamLocallyGenerated = false;

    // Flag to indicate PeerConnection ready for new actions.
    this._rtcReady = true;

    // SIP Timers.
    this._timers = new SIPTimers();

    // Session info.
    this._direction = null;
    this._local_identity = null;
    this._remote_identity = null;
    this._start_time = null;
    this._end_time = null;
    this._tones = null;

    // Mute/Hold state.
    this._audioMuted = false;
    this._videoMuted = false;
    this._localHold = false;
    this._remoteHold = false;

    // Session Timers (RFC 4028).
    this._sessionTimers = new RFC4028Timers(
        this._ua.configuration.session_timers,
        this._ua.configuration.session_timers_refresh_method,
        DartSIP_C.SESSION_EXPIRES,
        null,
        false,
        false,
        null);

    // Map of ReferSubscriber instances indexed by the REFER's CSeq number.
    this._referSubscribers = {};

    // Custom session empty object for high level use.
    this._data = {};

    this.receiveRequest = _receiveRequest;
  }

  /**
   * User API
   */

  // Expose session failed/ended causes as a property of the RTCSession instance.
  get causes => DartSIP_C.causes;

  get id => this._id;

  get connection => this._connection;

  get contact => this._contact;

  String get direction => this._direction;

  NameAddrHeader get local_identity => this._local_identity;

  NameAddrHeader get remote_identity => this._remote_identity;

  get start_time => this._start_time;

  get end_time => this._end_time;

  get data => this._data;

  get ua => this._ua;

  set data(_data) {
    this._data = _data;
  }

  get status => this._status;

  isInProgress() {
    switch (this._status) {
      case C.STATUS_NULL:
      case C.STATUS_INVITE_SENT:
      case C.STATUS_1XX_RECEIVED:
      case C.STATUS_INVITE_RECEIVED:
      case C.STATUS_WAITING_FOR_ANSWER:
        return true;
      default:
        return false;
    }
  }

  isEstablished() {
    switch (this._status) {
      case C.STATUS_ANSWERED:
      case C.STATUS_WAITING_FOR_ACK:
      case C.STATUS_CONFIRMED:
        return true;
      default:
        return false;
    }
  }

  isEnded() {
    switch (this._status) {
      case C.STATUS_CANCELED:
      case C.STATUS_TERMINATED:
        return true;
      default:
        return false;
    }
  }

  isMuted() {
    return {'audio': this._audioMuted, 'video': this._videoMuted};
  }

  isOnHold() {
    return {'local': this._localHold, 'remote': this._remoteHold};
  }

  connect(target, [options, initCallback]) async {
    debug('connect()');

    options = options ?? {};
    var originalTarget = target;
    var eventHandlers = options['eventHandlers'] ?? {};
    var extraHeaders = Utils.cloneArray(options['extraHeaders']);
    Map<String, dynamic> mediaConstraints =
        options['mediaConstraints'] ?? {'audio': true, 'video': true};
    var mediaStream = options['mediaStream'] ?? null;
    Map<String, dynamic> pcConfig = options['pcConfig'] ?? {'iceServers': []};
    Map<String, dynamic> rtcConstraints = options['rtcConstraints'] ?? {};
    Map<String, dynamic> rtcOfferConstraints =
        options['rtcOfferConstraints'] ?? {};
    this._rtcOfferConstraints = rtcOfferConstraints;
    this._rtcAnswerConstraints = options['rtcAnswerConstraints'] ?? {};
    this._data = options['data'] ?? this._data;

    // Check target.
    if (target == null) {
      throw new Exceptions.TypeError('Not enough arguments');
    }

    // Check Session Status.
    if (this._status != C.STATUS_NULL) {
      throw new Exceptions.InvalidStateError(this._status);
    }

    // Check WebRTC support.
    // TODO: change support for flutter-webrtc
    //if (RTCPeerConnection == null)
    //{
    //  throw new Exceptions.NotSupportedError('WebRTC not supported');
    //}

    // Check target validity.
    target = this._ua.normalizeTarget(target);
    if (target == null) {
      throw new Exceptions.TypeError('Invalid target: ${originalTarget}');
    }

    // Session Timers.
    if (this._sessionTimers.enabled) {
      if (Utils.isDecimal(options['sessionTimersExpires'])) {
        if (options['sessionTimersExpires'] >= DartSIP_C.MIN_SESSION_EXPIRES) {
          this._sessionTimers.defaultExpires = options['sessionTimersExpires'];
        } else {
          this._sessionTimers.defaultExpires = DartSIP_C.SESSION_EXPIRES;
        }
      }
    }

    // Set event handlers.
    eventHandlers.forEach((event, func) {
      this.on(event, func);
    });

    // Session parameter initialization.
    this._from_tag = Utils.newTag();

    // Set anonymous property.
    bool anonymous = options['anonymous'] ?? false;
    Map<String, dynamic> requestParams = {'from_tag': this._from_tag};
    this._ua.contact.anonymous = anonymous;
    this._ua.contact.outbound = true;
    this._contact = this._ua.contact.toString();

    if (anonymous) {
      requestParams['from_display_name'] = 'Anonymous';
      requestParams['from_uri'] =
          new URI('sip', 'anonymous', 'anonymous.invalid');
      extraHeaders.add(
          'P-Preferred-Identity: ${this._ua.configuration.uri.toString()}');
      extraHeaders.add('Privacy: id');
    }

    extraHeaders.add('Contact: ${this._contact}');
    extraHeaders.add('Content-Type: application/sdp');
    if (this._sessionTimers.enabled) {
      extraHeaders
          .add('Session-Expires: ${this._sessionTimers.defaultExpires}');
    }

    this._request = new SIPMessage.InitialOutgoingInviteRequest(
        target, this._ua, requestParams, extraHeaders);

    this._id = this._request.call_id + this._from_tag;

    // Create a new RTCPeerConnection instance.
    await this._createRTCConnection(pcConfig, rtcConstraints);

    // Set internal properties.
    this._direction = 'outgoing';
    this._local_identity = this._request.from;
    this._remote_identity = this._request.to;

    // User explicitly provided a newRTCSession callback for this session.
    if (initCallback != null) {
      initCallback(this);
    }

    this._newRTCSession('local', this._request);
    await this._sendInitialRequest(
        mediaConstraints, rtcOfferConstraints, mediaStream);
  }

  init_incoming(request, [initCallback]) {
    debug('init_incoming()');

    var expires;
    var contentType = request.getHeader('Content-Type');

    // Check body and content type.
    if (request.body != null && (contentType != 'application/sdp')) {
      request.reply(415);
      return;
    }

    // Session parameter initialization.
    this._status = C.STATUS_INVITE_RECEIVED;
    this._from_tag = request.from_tag;
    this._id = request.call_id + this._from_tag;
    this._request = request;
    this._contact = this._ua.contact.toString();

    // Get the Expires header value if exists.
    if (request.hasHeader('expires')) {
      expires = request.getHeader('expires') * 1000;
    }

    /* Set the to_tag before
     * replying a response code that will create a dialog.
     */
    request.to_tag = Utils.newTag();

    // An error on dialog creation will fire 'failed' event.
    if (!this._createDialog(request, 'UAS', true)) {
      request.reply(500, 'Missing Contact header field');
      return;
    }

    if (request.body != null) {
      this._late_sdp = false;
    } else {
      this._late_sdp = true;
    }

    this._status = C.STATUS_WAITING_FOR_ANSWER;

    // Set userNoAnswerTimer.
    this._timers.userNoAnswerTimer = setTimeout(() {
      request.reply(408);
      this._failed('local', null, DartSIP_C.causes.NO_ANSWER);
    }, this._ua.configuration.no_answer_timeout);

    /* Set expiresTimer
     * RFC3261 13.3.1
     */
    if (expires != null) {
      this._timers.expiresTimer = setTimeout(() {
        if (this._status == C.STATUS_WAITING_FOR_ANSWER) {
          request.reply(487);
          this._failed('system', null, DartSIP_C.causes.EXPIRES);
        }
      }, expires);
    }

    // Set internal properties.
    this._direction = 'incoming';
    this._local_identity = request.to;
    this._remote_identity = request.from;

    // A init callback was specifically defined.
    if (initCallback != null) {
      initCallback(this);
    }

    // Fire 'newRTCSession' event.
    this._newRTCSession('remote', request);

    // The user may have rejected the call in the 'newRTCSession' event.
    if (this._status == C.STATUS_TERMINATED) {
      return;
    }

    // Reply 180.
    request.reply(180, null, ['Contact: ${this._contact}']);

    // Fire 'progress' event.
    // TODO: Document that 'response' field in 'progress' event is null for incoming calls.
    this._progress('local', null);
  }

  /**
   * Answer the call.
   */
  answer(options) async {
    debug('answer()');
    var request = this._request;
    var extraHeaders = Utils.cloneArray(options['extraHeaders']);
    var mediaConstraints = options['mediaConstraints'] ?? {};
    var mediaStream = options['mediaStream'] ?? null;
    var pcConfig = options['pcConfig'] ?? {'iceServers': []};
    var rtcConstraints = options['rtcConstraints'] ?? {};
    var rtcAnswerConstraints = options['rtcAnswerConstraints'] ?? {};

    var tracks;
    var peerHasAudioLine = false;
    var peerHasVideoLine = false;
    var peerOffersFullAudio = false;
    var peerOffersFullVideo = false;

    this._rtcAnswerConstraints = rtcAnswerConstraints;
    this._rtcOfferConstraints = options['rtcOfferConstraints'] ?? null;

    this._data = options['data'] ?? this._data;

    // Check Session Direction and Status.
    if (this._direction != 'incoming') {
      throw new Exceptions.NotSupportedError(
          '"answer" not supported for outgoing RTCSession');
    }

    // Check Session status.
    if (this._status != C.STATUS_WAITING_FOR_ANSWER) {
      throw new Exceptions.InvalidStateError(this._status);
    }

    // Session Timers.
    if (this._sessionTimers.enabled) {
      if (Utils.isDecimal(options['sessionTimersExpires'])) {
        if (options['sessionTimersExpires'] >= DartSIP_C.MIN_SESSION_EXPIRES) {
          this._sessionTimers.defaultExpires = options['sessionTimersExpires'];
        } else {
          this._sessionTimers.defaultExpires = DartSIP_C.SESSION_EXPIRES;
        }
      }
    }

    this._status = C.STATUS_ANSWERED;

    // An error on dialog creation will fire 'failed' event.
    if (!this._createDialog(request, 'UAS')) {
      request.reply(500, 'Error creating dialog');

      return;
    }

    clearTimeout(this._timers.userNoAnswerTimer);
    extraHeaders.insert(0, 'Contact: ${this._contact}');

    // Determine incoming media from incoming SDP offer (if any).
    var sdp = request.parseSDP();

    // Make sure sdp['media'] is an array, not the case if there is only one media.
    if (sdp['media'] is! List) {
      sdp['media'] = [sdp['media']];
    }

    // Go through all medias in SDP to find offered capabilities to answer with.
    for (var m in sdp['media']) {
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
      for (var track in tracks) {
        mediaStream.removeTrack(track);
      }
    }

    // Remove video from mediaStream if suggested by mediaConstraints.
    if (mediaStream != null && mediaConstraints['video'] == false) {
      tracks = mediaStream.getVideoTracks();
      for (var track in tracks) {
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

    // Create a new RTCPeerConnection instance.
    // TODO: This may throw an error, should react.
    await this._createRTCConnection(pcConfig, rtcConstraints);

    var stream;
    // A local MediaStream is given, use it.
    if (mediaStream != null) {
      stream = mediaStream;
    }
    // Audio and/or video requested, prompt getUserMedia.
    else if (mediaConstraints['audio'] != null ||
        mediaConstraints['video'] != null) {
      this._localMediaStreamLocallyGenerated = true;
      try {
        stream = await navigator.getUserMedia(mediaConstraints);
        var e = {'originator': 'local', 'stream': stream};
        this.emit('stream', e);
      } catch (error) {
        if (this._status == C.STATUS_TERMINATED) {
          throw new Exceptions.InvalidStateError('terminated');
        }
        request.reply(480);
        this._failed('local', null, DartSIP_C.causes.USER_DENIED_MEDIA_ACCESS);
        debugerror('emit "getusermediafailed" [error:${error.toString()}]');
        this.emit('getusermediafailed', error);
        throw new Exceptions.InvalidStateError('getUserMedia() failed');
      }
    }

    if (this._status == C.STATUS_TERMINATED) {
      throw new Exceptions.InvalidStateError('terminated');
    }

    // Attach MediaStream to RTCPeerconnection.
    this._localMediaStream = stream;
    if (stream != null) {
      this._connection.addStream(stream);
    }

    // Set remote description.
    if (this._late_sdp) {
      return;
    }

    var e = {'originator': 'remote', 'type': 'offer', 'sdp': request.body};

    debug('emit "sdp"');
    this.emit('sdp', e);

    var offer = new RTCSessionDescription(request.body, 'offer');
    try {
      await this._connection.setRemoteDescription(offer);
    } catch (error) {
      request.reply(488);
      this._failed('system', null, DartSIP_C.causes.WEBRTC_ERROR);
      debugerror(
          'emit "peerconnection:setremotedescriptionfailed" [error:${error.toString()}]');
      this.emit('peerconnection:setremotedescriptionfailed', error);
      throw new Exceptions.TypeError(
          'peerconnection.setRemoteDescription() failed');
    }

    // Create local description.
    if (this._status == C.STATUS_TERMINATED) {
      throw new Exceptions.InvalidStateError('terminated');
    }

    // TODO: Is this event already useful?
    this._connecting(request);
    var desc;
    try {
      if (!this._late_sdp) {
        desc =
            await this._createLocalDescription('answer', rtcAnswerConstraints);
      } else {
        desc = await this
            ._createLocalDescription('offer', this._rtcOfferConstraints);
      }
    } catch (e) {
      request.reply(500);
      throw new Exceptions.TypeError('_createLocalDescription() failed');
    }

    if (this._status == C.STATUS_TERMINATED) {
      throw new Exceptions.InvalidStateError('terminated');
    }

    // Send reply.
    try {
      this._handleSessionTimersInIncomingRequest(request, extraHeaders);
      request.reply(200, null, extraHeaders, desc.sdp, () {
        this._status = C.STATUS_WAITING_FOR_ACK;
        this._setInvite2xxTimer(request, desc.sdp);
        this._setACKTimer();
        this._accepted('local');
      }, () {
        this._failed('system', null, DartSIP_C.causes.CONNECTION_ERROR);
      });
    } catch (error) {
      if (this._status == C.STATUS_TERMINATED) {
        return;
      }
      debugerror(error.toString());
    }
  }

  /**
   * Terminate the call.
   */
  terminate([Map<String, Object> options]) {
    debug('terminate()');

    options = options ?? {};

    var cause = options['cause'] ?? DartSIP_C.causes.BYE;
    var extraHeaders = Utils.cloneArray(options['extraHeaders']);
    var body = options['body'];

    var cancel_reason;
    int status_code = options['status_code'];
    var reason_phrase = options['reason_phrase'];

    // Check Session Status.
    if (this._status == C.STATUS_TERMINATED) {
      throw new Exceptions.InvalidStateError(this._status);
    }

    switch (this._status) {
      // - UAC -
      case C.STATUS_NULL:
      case C.STATUS_INVITE_SENT:
      case C.STATUS_1XX_RECEIVED:
        debug('canceling session');

        if (status_code != null && (status_code < 200 || status_code >= 700)) {
          throw new Exceptions.TypeError('Invalid status_code: ${status_code}');
        } else if (status_code != null) {
          reason_phrase =
              reason_phrase ?? DartSIP_C.REASON_PHRASE[status_code] ?? '';
          cancel_reason = 'SIP ;cause=${status_code} ;text="${reason_phrase}"';
        }

        // Check Session Status.
        if (this._status == C.STATUS_NULL ||
            this._status == C.STATUS_INVITE_SENT) {
          this._is_canceled = true;
          this._cancel_reason = cancel_reason;
        } else if (this._status == C.STATUS_1XX_RECEIVED) {
          this._request.cancel(cancel_reason);
        }

        this._status = C.STATUS_CANCELED;
        this._failed('local', null, DartSIP_C.causes.CANCELED);
        break;

      // - UAS -
      case C.STATUS_WAITING_FOR_ANSWER:
      case C.STATUS_ANSWERED:
        debug('rejecting session');

        status_code = status_code ?? 480;

        if (status_code < 300 || status_code >= 700) {
          throw new Exceptions.InvalidStateError(
              'Invalid status_code: ${status_code}');
        }

        this._request.reply(status_code, reason_phrase, extraHeaders, body);
        this._failed('local', null, DartSIP_C.causes.REJECTED);
        break;

      case C.STATUS_WAITING_FOR_ACK:
      case C.STATUS_CONFIRMED:
        debug('terminating session');

        reason_phrase = options['reason_phrase'] ??
            DartSIP_C.REASON_PHRASE[status_code] ??
            '';

        if (status_code != null && (status_code < 200 || status_code >= 700)) {
          throw new Exceptions.InvalidStateError(
              'Invalid status_code: ${status_code}');
        } else if (status_code != null) {
          extraHeaders.add(
              'Reason: SIP ;cause=${status_code}; text="${reason_phrase}"');
        }

        /* RFC 3261 section 15 (Terminating a session):
          *
          * "...the callee's UA MUST NOT send a BYE on a confirmed dialog
          * until it has received an ACK for its 2xx response or until the server
          * transaction times out."
          */
        if (this._status == C.STATUS_WAITING_FOR_ACK &&
            this._direction == 'incoming' &&
            this._request.server_transaction.state !=
                TransactionState.TERMINATED) {
          /// Save the dialog for later restoration.
          Dialog dialog = this._dialog;

          // Send the BYE as soon as the ACK is received...
          this.receiveRequest = (IncomingMessage request) {
            if (request.method == SipMethod.ACK) {
              this.sendRequest(
                  SipMethod.BYE, {'extraHeaders': extraHeaders, 'body': body});
              dialog.terminate();
            }
          };

          // .., or when the INVITE transaction times out
          this._request.server_transaction.on('stateChanged', () {
            if (this._request.server_transaction.state ==
                TransactionState.TERMINATED) {
              this.sendRequest(
                  SipMethod.BYE, {'extraHeaders': extraHeaders, 'body': body});
              dialog.terminate();
            }
          });

          this._ended('local', null, cause);

          // Restore the dialog into 'this' in order to be able to send the in-dialog BYE :-).
          this._dialog = dialog;

          // Restore the dialog into 'ua' so the ACK can reach 'this' session.
          this._ua.newDialog(dialog);
        } else {
          this.sendRequest(
              SipMethod.BYE, {'extraHeaders': extraHeaders, 'body': body});

          this._ended('local', null, cause);
        }
    }
  }

  sendDTMF(tones, options) {
    debug('sendDTMF() | tones: ${tones.toString()}');

    var position = 0;
    var duration = options['duration'] ?? null;
    var interToneGap = options['interToneGap'] ?? null;

    if (tones == null) {
      throw new Exceptions.TypeError('Not enough arguments');
    }

    // Check Session Status.
    if (this._status != C.STATUS_CONFIRMED &&
        this._status != C.STATUS_WAITING_FOR_ACK) {
      throw new Exceptions.InvalidStateError(this._status);
    }

    // Convert to string.
    if (tones is num) {
      tones = tones.toString();
    }

    // Check tones.
    if (tones == null ||
        tones is! String ||
        !tones.contains(new RegExp(r'^[0-9A-DR#*,]+$', caseSensitive: false))) {
      throw new Exceptions.TypeError('Invalid tones: ${tones.toString()}');
    }

    // Check duration.
    if (duration && !Utils.isDecimal(duration)) {
      throw new Exceptions.TypeError(
          'Invalid tone duration: ${duration.toString()}');
    } else if (duration == null) {
      duration = RTCSession_DTMF.C.DEFAULT_DURATION;
    } else if (duration < RTCSession_DTMF.C.MIN_DURATION) {
      debug(
          '"duration" value is lower than the minimum allowed, setting it to ${RTCSession_DTMF.C.MIN_DURATION} milliseconds');
      duration = RTCSession_DTMF.C.MIN_DURATION;
    } else if (duration > RTCSession_DTMF.C.MAX_DURATION) {
      debug(
          '"duration" value is greater than the maximum allowed, setting it to ${RTCSession_DTMF.C.MAX_DURATION} milliseconds');
      duration = RTCSession_DTMF.C.MAX_DURATION;
    } else {
      duration = Utils.Math.abs(duration);
    }
    options['duration'] = duration;

    // Check interToneGap.
    if (interToneGap && !Utils.isDecimal(interToneGap)) {
      throw new Exceptions.TypeError(
          'Invalid interToneGap: ${interToneGap.toString()}');
    } else if (interToneGap == null) {
      interToneGap = RTCSession_DTMF.C.DEFAULT_INTER_TONE_GAP;
    } else if (interToneGap < RTCSession_DTMF.C.MIN_INTER_TONE_GAP) {
      debug(
          '"interToneGap" value is lower than the minimum allowed, setting it to ${RTCSession_DTMF.C.MIN_INTER_TONE_GAP} milliseconds');
      interToneGap = RTCSession_DTMF.C.MIN_INTER_TONE_GAP;
    } else {
      interToneGap = Utils.Math.abs(interToneGap);
    }

    if (this._tones != null) {
      // Tones are already queued, just add to the queue.
      this._tones += tones;
      return;
    }

    this._tones = tones;

    _sendDTMF = () {
      var timeout;

      if (this._status == C.STATUS_TERMINATED ||
          !this._tones ||
          position >= this._tones.length) {
        // Stop sending DTMF.
        this._tones = null;

        return;
      }

      var tone = this._tones[position];

      position += 1;

      if (tone == ',') {
        timeout = 2000;
      } else {
        var dtmf = new RTCSession_DTMF.DTMF(this);

        options['eventHandlers'] = {
          'onFailed': () {
            this._tones = null;
          }
        };
        dtmf.send(tone, options);
        timeout = duration + interToneGap;
      }

      // Set timeout for the next tone.
      setTimeout(() => _sendDTMF, timeout);
    };

    // Send the first tone.
    _sendDTMF();
  }

  sendInfo(contentType, body, options) {
    debug('sendInfo()');

    // Check Session Status.
    if (this._status != C.STATUS_CONFIRMED &&
        this._status != C.STATUS_WAITING_FOR_ACK) {
      throw new Exceptions.InvalidStateError(this._status);
    }

    var info = new RTCSession_Info.Info(this);

    info.send(contentType, body, options);
  }

  /**
   * Mute
   */
  mute([audio = true, video = true]) {
    debug('mute()');

    var audioMuted = false, videoMuted = false;

    if (this._audioMuted == false && audio) {
      audioMuted = true;
      this._audioMuted = true;
      this._toggleMuteAudio(true);
    }

    if (this._videoMuted == false && video) {
      videoMuted = true;
      this._videoMuted = true;
      this._toggleMuteVideo(true);
    }

    if (audioMuted == true || videoMuted == true) {
      this._onmute(audioMuted, videoMuted);
    }
  }

  /**
   * Unmute
   */
  unmute([audio = true, video = true]) {
    debug('unmute()');

    var audioUnMuted = false, videoUnMuted = false;

    if (this._audioMuted == true && audio) {
      audioUnMuted = true;
      this._audioMuted = false;

      if (this._localHold == false) {
        this._toggleMuteAudio(false);
      }
    }

    if (this._videoMuted == true && video) {
      videoUnMuted = true;
      this._videoMuted = false;

      if (this._localHold == false) {
        this._toggleMuteVideo(false);
      }
    }

    if (audioUnMuted == true || videoUnMuted == true) {
      this._onunmute(audioUnMuted, videoUnMuted);
    }
  }

  /**
   * Hold
   */
  hold([options, done]) {
    debug('hold()');

    options = options ?? {};

    if (this._status != C.STATUS_WAITING_FOR_ACK &&
        this._status != C.STATUS_CONFIRMED) {
      return false;
    }

    if (this._localHold == true) {
      return false;
    }

    if (!this._isReadyToReOffer()) {
      return false;
    }

    this._localHold = true;
    this._onhold('local');

    var eventHandlers = {
      'succeeded': (response) {
        if (done != null) {
          done();
        }
      },
      'failed': (response) {
        this.terminate({
          'cause': DartSIP_C.causes.WEBRTC_ERROR,
          'status_code': 500,
          'reason_phrase': 'Hold Failed'
        });
      }
    };

    if (options['useUpdate'] != null) {
      this._sendUpdate({
        'sdpOffer': true,
        'eventHandlers': eventHandlers,
        'extraHeaders': options['extraHeaders']
      });
    } else {
      this._sendReinvite({
        'eventHandlers': eventHandlers,
        'extraHeaders': options['extraHeaders']
      });
    }

    return true;
  }

  unhold([options, done]) {
    debug('unhold()');

    options = options ?? {};

    if (this._status != C.STATUS_WAITING_FOR_ACK &&
        this._status != C.STATUS_CONFIRMED) {
      return false;
    }

    if (this._localHold == false) {
      return false;
    }

    if (!this._isReadyToReOffer()) {
      return false;
    }

    this._localHold = false;
    this._onunhold('local');

    var eventHandlers = {
      'succeeded': (response) {
        if (done != null) {
          done();
        }
      },
      'failed': (response) {
        this.terminate({
          'cause': DartSIP_C.causes.WEBRTC_ERROR,
          'status_code': 500,
          'reason_phrase': 'Unhold Failed'
        });
      }
    };

    if (options['useUpdate'] != null) {
      this._sendUpdate({
        'sdpOffer': true,
        'eventHandlers': eventHandlers,
        'extraHeaders': options['extraHeaders']
      });
    } else {
      this._sendReinvite({
        'eventHandlers': eventHandlers,
        'extraHeaders': options['extraHeaders']
      });
    }

    return true;
  }

  renegotiate([options, done]) {
    debug('renegotiate()');

    options = options ?? {};

    var rtcOfferConstraints = options['rtcOfferConstraints'] ?? null;

    if (this._status != C.STATUS_WAITING_FOR_ACK &&
        this._status != C.STATUS_CONFIRMED) {
      return false;
    }

    if (!this._isReadyToReOffer()) {
      return false;
    }

    var eventHandlers = {
      'succeeded': (response) {
        if (done != null) {
          done();
        }
      },
      'failed': (response) {
        this.terminate({
          'cause': DartSIP_C.causes.WEBRTC_ERROR,
          'status_code': 500,
          'reason_phrase': 'Media Renegotiation Failed'
        });
      }
    };

    this._setLocalMediaStatus();

    if (options['useUpdate'] != null) {
      this._sendUpdate({
        'sdpOffer': true,
        'eventHandlers': eventHandlers,
        'rtcOfferConstraints': rtcOfferConstraints,
        'extraHeaders': options['extraHeaders']
      });
    } else {
      this._sendReinvite({
        'eventHandlers': eventHandlers,
        'rtcOfferConstraints': rtcOfferConstraints,
        'extraHeaders': options['extraHeaders']
      });
    }

    return true;
  }

  /**
   * Refer
   */
  refer(target, [options]) {
    debug('refer()');

    options = options ?? {};

    var originalTarget = target;

    if (this._status != C.STATUS_WAITING_FOR_ACK &&
        this._status != C.STATUS_CONFIRMED) {
      return false;
    }

    // Check target validity.
    target = this._ua.normalizeTarget(target);
    if (target == null) {
      throw new Exceptions.TypeError('Invalid target: ${originalTarget}');
    }

    var referSubscriber = new RTCSession_ReferSubscriber.ReferSubscriber(this);

    referSubscriber.sendRefer(target, options);

    // Store in the map.
    var id = referSubscriber.id;

    this._referSubscribers[id] = referSubscriber;

    // Listen for ending events so we can remove it from the map.
    referSubscriber.on('requestFailed', () {
      this._referSubscribers.remove(id);
    });
    referSubscriber.on('accepted', () {
      this._referSubscribers.remove(id);
    });
    referSubscriber.on('failed', () {
      this._referSubscribers.remove(id);
    });

    return referSubscriber;
  }

  /**
   * Send a generic in-dialog Request
   */
  sendRequest(SipMethod method, [options]) {
    debug('sendRequest()');

    return this._dialog.sendRequest(method, options);
  }

  /**
   * In dialog Request Reception
   */
  _receiveRequest(request) async {
    debug('receiveRequest()');

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
      if (this._status == C.STATUS_WAITING_FOR_ANSWER ||
          this._status == C.STATUS_ANSWERED) {
        this._status = C.STATUS_CANCELED;
        this._request.reply(487);
        this._failed('remote', request, DartSIP_C.causes.CANCELED);
      }
    } else {
      // Requests arriving here are in-dialog requests.
      switch (request.method) {
        case SipMethod.ACK:
          if (this._status != C.STATUS_WAITING_FOR_ACK) {
            return;
          }
          // Update signaling status.
          this._status = C.STATUS_CONFIRMED;
          clearTimeout(this._timers.ackTimer);
          clearTimeout(this._timers.invite2xxTimer);

          if (this._late_sdp) {
            if (request.body == null) {
              this.terminate(
                  {'cause': DartSIP_C.causes.MISSING_SDP, 'status_code': 400});
              break;
            }

            var e = {
              'originator': 'remote',
              'type': 'answer',
              'sdp': request.body
            };
            debug('emit "sdp"');
            this.emit('sdp', e);

            var answer = new RTCSessionDescription(request.body, 'answer');
            try {
              await this._connection.setRemoteDescription(answer);
            } catch (error) {
              this.terminate({
                'cause': DartSIP_C.causes.BAD_MEDIA_DESCRIPTION,
                'status_code': 488
              });
              debugerror(
                  'emit "peerconnection:setremotedescriptionfailed" [error:${error.toString()}]');
              this.emit('peerconnection:setremotedescriptionfailed', error);
            }
          }
          if (!this._is_confirmed) {
            this._confirmed('remote', request);
          }
          break;
        case SipMethod.BYE:
          if (this._status == C.STATUS_CONFIRMED) {
            request.reply(200);
            this._ended('remote', request, DartSIP_C.causes.BYE);
          } else if (this._status == C.STATUS_INVITE_RECEIVED) {
            request.reply(200);
            this._request.reply(487, 'BYE Received');
            this._ended('remote', request, DartSIP_C.causes.BYE);
          } else {
            request.reply(403, 'Wrong Status');
          }
          break;
        case SipMethod.INVITE:
          if (this._status == C.STATUS_CONFIRMED) {
            if (request.hasHeader('replaces')) {
              this._receiveReplaces(request);
            } else {
              this._receiveReinvite(request);
            }
          } else {
            request.reply(403, 'Wrong Status');
          }
          break;
        case SipMethod.INFO:
          if (this._status == C.STATUS_1XX_RECEIVED ||
              this._status == C.STATUS_WAITING_FOR_ANSWER ||
              this._status == C.STATUS_ANSWERED ||
              this._status == C.STATUS_WAITING_FOR_ACK ||
              this._status == C.STATUS_CONFIRMED) {
            var contentType = request.getHeader('content-type');
            if (contentType &&
                contentType.contains(new RegExp(r'^application\/dtmf-relay',
                    caseSensitive: false))) {
              new RTCSession_DTMF.DTMF(this).init_incoming(request);
            } else if (contentType != null) {
              new RTCSession_Info.Info(this).init_incoming(request);
            } else {
              request.reply(415);
            }
          } else {
            request.reply(403, 'Wrong Status');
          }
          break;
        case SipMethod.UPDATE:
          if (this._status == C.STATUS_CONFIRMED) {
            this._receiveUpdate(request);
          } else {
            request.reply(403, 'Wrong Status');
          }
          break;
        case SipMethod.REFER:
          if (this._status == C.STATUS_CONFIRMED) {
            this._receiveRefer(request);
          } else {
            request.reply(403, 'Wrong Status');
          }
          break;
        case SipMethod.NOTIFY:
          if (this._status == C.STATUS_CONFIRMED) {
            this._receiveNotify(request);
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
  onTransportError() {
    debugerror('onTransportError()');
    if (this._status != C.STATUS_TERMINATED) {
      this.terminate({
        'status_code': 500,
        'reason_phrase': DartSIP_C.causes.CONNECTION_ERROR,
        'cause': DartSIP_C.causes.CONNECTION_ERROR
      });
    }
  }

  onRequestTimeout() {
    debugerror('onRequestTimeout()');

    if (this._status != C.STATUS_TERMINATED) {
      this.terminate({
        'status_code': 408,
        'reason_phrase': DartSIP_C.causes.REQUEST_TIMEOUT,
        'cause': DartSIP_C.causes.REQUEST_TIMEOUT
      });
    }
  }

  onDialogError() {
    debugerror('onDialogError()');

    if (this._status != C.STATUS_TERMINATED) {
      this.terminate({
        'status_code': 500,
        'reason_phrase': DartSIP_C.causes.DIALOG_ERROR,
        'cause': DartSIP_C.causes.DIALOG_ERROR
      });
    }
  }

  // Called from DTMF handler.
  newDTMF(data) {
    debug('newDTMF()');

    this.emit('newDTMF', data);
  }

  // Called from Info handler.
  newInfo(data) {
    debug('newInfo()');

    this.emit('newInfo', data);
  }

  /**
   * Check if RTCSession is ready for an outgoing re-INVITE or UPDATE with SDP.
   */
  _isReadyToReOffer() {
    if (!this._rtcReady) {
      debug('_isReadyToReOffer() | internal WebRTC status not ready');

      return false;
    }

    // No established yet.
    if (this._dialog == null) {
      debug('_isReadyToReOffer() | session not established yet');

      return false;
    }

    // Another INVITE transaction is in progress.
    if (this._dialog.uac_pending_reply == true ||
        this._dialog.uas_pending_reply == true) {
      debug(
          '_isReadyToReOffer() | there is another INVITE/UPDATE transaction in progress');

      return false;
    }

    return true;
  }

  _close() async {
    debug('close()');
    if (this._status == C.STATUS_TERMINATED) {
      return;
    }
    this._status = C.STATUS_TERMINATED;
    // Terminate RTC.
    if (this._connection != null) {
      try {
        await this._connection.close();
        await this._connection.dispose();
        this._connection = null;
      } catch (error) {
        debugerror(
            'close() | error closing the RTCPeerConnection: ${error.toString()}');
      }
    }
    // Close local MediaStream if it was not given by the user.
    if (this._localMediaStream != null &&
        this._localMediaStreamLocallyGenerated) {
      debug('close() | closing local MediaStream');
      await this._localMediaStream.dispose();
      this._localMediaStream = null;
    }

    // Terminate signaling.

    // Clear SIP timers.
    clearTimeout(this._timers.ackTimer);
    clearTimeout(this._timers.expiresTimer);
    clearTimeout(this._timers.invite2xxTimer);
    clearTimeout(this._timers.userNoAnswerTimer);

    // Clear Session Timers.
    clearTimeout(this._sessionTimers.timer);

    // Terminate confirmed dialog.
    if (this._dialog != null) {
      this._dialog.terminate();
      this._dialog = null;
    }

    // Terminate early dialogs.
    this._earlyDialogs.forEach((dialog, _) {
      this._earlyDialogs[dialog].terminate();
    });
    this._earlyDialogs.clear();

    // Terminate REFER subscribers.
    this._referSubscribers.clear();

    this._ua.destroyRTCSession(this);
  }

  /**
   * Private API.
   */

  /**
   * RFC3261 13.3.1.4
   * Response retransmissions cannot be accomplished by transaction layer
   *  since it is destroyed when receiving the first 2xx answer
   */
  _setInvite2xxTimer(request, body) {
    var timeout = Timers.T1;

    invite2xxRetransmission() {
      if (this._status != C.STATUS_WAITING_FOR_ACK) {
        return;
      }
      request.reply(200, null, ['Contact: ${this._contact}'], body);
      if (timeout < Timers.T2) {
        timeout = timeout * 2;
        if (timeout > Timers.T2) {
          timeout = Timers.T2;
        }
      }
      this._timers.invite2xxTimer =
          setTimeout(invite2xxRetransmission, timeout);
    }

    this._timers.invite2xxTimer = setTimeout(invite2xxRetransmission, timeout);
  }

  /**
   * RFC3261 14.2
   * If a UAS generates a 2xx response and never receives an ACK,
   *  it SHOULD generate a BYE to terminate the dialog.
   */
  _setACKTimer() {
    this._timers.ackTimer = setTimeout(() {
      if (this._status == C.STATUS_WAITING_FOR_ACK) {
        debug('no ACK received, terminating the session');

        clearTimeout(this._timers.invite2xxTimer);
        this.sendRequest(SipMethod.BYE);
        this._ended('remote', null, DartSIP_C.causes.NO_ACK);
      }
    }, Timers.TIMER_H);
  }

  Future<void> _createRTCConnection(pcConfig, rtcConstraints) async {
    this._connection = await createPeerConnection(pcConfig, rtcConstraints);
    this._connection.onIceConnectionState = (state) {
      // TODO: Do more with different states.
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        this.terminate({
          'cause': DartSIP_C.causes.RTP_TIMEOUT,
          'status_code': 408,
          'reason_phrase': DartSIP_C.causes.RTP_TIMEOUT
        });
      }
    };

    this._connection.onAddStream = (stream) {
      var e = {'originator': 'remote', 'stream': stream};
      this.emit('stream', e);
    };

    debug('emit "peerconnection"');
    this.emit('peerconnection', {'peerconnection': this._connection});
    return;
  }

  FutureOr<RTCSessionDescription> _createLocalDescription(
      type, constraints) async {
    debug('createLocalDescription()');

    Completer<RTCSessionDescription> completer =
        new Completer<RTCSessionDescription>();

    if (type != 'offer' && type != 'answer') {
      completer.completeError(new Exceptions.TypeError(
          'createLocalDescription() | invalid type "${type}"'));
    }

    this._rtcReady = false;
    var desc;
    if (type == 'offer') {
      try {
        desc = await this._connection.createOffer(constraints);
      } catch (error) {
        debugerror(
            'emit "peerconnection:createofferfailed" [error:${error.toString()}]');
        this.emit('peerconnection:createofferfailed', error);
        completer.completeError(error);
      }
    } else {
      try {
        desc = await this._connection.createAnswer(constraints);
      } catch (error) {
        debugerror(
            'emit "peerconnection:createanswerfailed" [error:${error.toString()}]');
        this.emit('peerconnection:createanswerfailed', error);
        completer.completeError(error);
      }
    }

    // Add 'pc.onicencandidate' event handler to resolve on last candidate.
    var finished = false;
    var ready = () async {
      this._connection.onIceCandidate = null;
      this._connection.onIceGatheringState = null;
      this._connection.onIceConnectionState = null;
      this._iceGatheringState =
          RTCIceGatheringState.RTCIceGatheringStateComplete;
      finished = true;
      this._rtcReady = true;
      var desc = await this._connection.getLocalDescription();
      var e = {'originator': 'local', 'type': type, 'sdp': desc.sdp};
      debug('emit "sdp"');
      this.emit('sdp', e);
      completer.complete(desc);
    };

    this._connection.onIceGatheringState = (state) {
      this._iceGatheringState = state;
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        if (!finished) {
          ready();
        }
      }
    };

    this._connection.onIceCandidate = (candidate) {
      if (candidate != null) {
        this.emit('icecandidate', {'candidate': candidate, 'ready': ready});
        if (!finished) {
          ready();
        }
      }
    };

    try {
      await this._connection.setLocalDescription(desc);
    } catch (error) {
      this._rtcReady = true;
      debugerror(
          'emit "peerconnection:setlocaldescriptionfailed" [error:${error.toString()}]');
      this.emit('peerconnection:setlocaldescriptionfailed', error);
      completer.completeError(error);
    }

    // Resolve right away if 'pc.iceGatheringState' is 'complete'.
    if (this._iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      this._rtcReady = true;
      var desc = await this._connection.getLocalDescription();
      var e = {'originator': 'local', 'type': type, 'sdp': desc.sdp};
      debug('emit "sdp"');
      this.emit('sdp', e);
      return desc;
    }

    return completer.future;
  }

  /**
   * Dialog Management
   */
  bool _createDialog(message, type, [early]) {
    var local_tag = (type == 'UAS') ? message.to_tag : message.from_tag;
    var remote_tag = (type == 'UAS') ? message.from_tag : message.to_tag;
    var id = message.call_id + local_tag + remote_tag;
    Dialog early_dialog = this._earlyDialogs[id];

    // Early Dialog.
    if (early != null) {
      if (early_dialog != null) {
        return true;
      } else {
        try {
          early_dialog = new Dialog(this, message, type, Dialog_C.STATUS_EARLY);
        } catch (error) {
          debug(error);
          this._failed('remote', message, DartSIP_C.causes.INTERNAL_ERROR);
          return false;
        }
        // Dialog has been successfully created.
        this._earlyDialogs[id] = early_dialog;
        return true;
      }
    } else // Confirmed Dialog.
    {
      this._from_tag = message.from_tag;
      this._to_tag = message.to_tag;

      // In case the dialog is in _early_ state, update it.
      if (early_dialog != null) {
        early_dialog.update(message, type);
        this._dialog = early_dialog;
        this._earlyDialogs.remove(id);
        return true;
      }

      try {
        // Otherwise, create a _confirmed_ dialog.
        this._dialog = new Dialog(this, message, type);
        return true;
      } catch (error) {
        debug(error.toString());
        this._failed('remote', message, DartSIP_C.causes.INTERNAL_ERROR);
        return false;
      }
    }
  }

  /// In dialog INVITE Reception
  void _receiveReinvite(request) async {
    debug('receiveReinvite()');

    var contentType = request.getHeader('Content-Type');
    var rejected = false;

    reject(options) {
      rejected = true;

      var status_code = options['status_code'] ?? 403;
      var reason_phrase = options['reason_phrase'] ?? '';
      var extraHeaders = Utils.cloneArray(options['extraHeaders']);

      if (this._status != C.STATUS_CONFIRMED) {
        return false;
      }

      if (status_code < 300 || status_code >= 700) {
        throw new Exceptions.TypeError('Invalid status_code: ${status_code}');
      }

      request.reply(status_code, reason_phrase, extraHeaders);
    }

    var data = {'request': request, 'callback': null, 'reject': reject};

    // Emit 'reinvite'.
    this.emit('reinvite', data);

    if (rejected) {
      return;
    }

    this._late_sdp = false;

    void sendAnswer(String sdp) async {
      var extraHeaders = ['Contact: ${this._contact}'];

      this._handleSessionTimersInIncomingRequest(request, extraHeaders);

      if (this._late_sdp) {
        sdp = this._mangleOffer(sdp);
      }

      request.reply(200, null, extraHeaders, sdp, () {
        this._status = C.STATUS_WAITING_FOR_ACK;
        this._setInvite2xxTimer(request, sdp);
        this._setACKTimer();
      });

      // If callback is given execute it.
      if (data['callback'] is Function) {
        data['callback']();
      }
    }

    // Request without SDP.
    if (request.body == null) {
      this._late_sdp = true;

      try {
        var desc = await this
            ._createLocalDescription('offer', this._rtcOfferConstraints);
        sendAnswer(desc.sdp);
      } catch (_) {
        request.reply(500);
      }
      return;
    }

    // Request with SDP.
    if (contentType != 'application/sdp') {
      debug('invalid Content-Type');
      request.reply(415);
      return;
    }

    try {
      var desc = await this._processInDialogSdpOffer(request);
      // Send answer.
      if (this._status == C.STATUS_TERMINATED) {
        return;
      }
      sendAnswer(desc.sdp);
    } catch (error) {
      debugerror(error);
    }
  }

  /**
   * In dialog UPDATE Reception
   */
  void _receiveUpdate(request) async {
    debug('receiveUpdate()');

    var rejected = false;

    reject(options) {
      rejected = true;

      var status_code = options['status_code'] ?? 403;
      var reason_phrase = options['reason_phrase'] ?? '';
      var extraHeaders = Utils.cloneArray(options['extraHeaders']);

      if (this._status != C.STATUS_CONFIRMED) {
        return false;
      }

      if (status_code < 300 || status_code >= 700) {
        throw new Exceptions.TypeError('Invalid status_code: ${status_code}');
      }

      request.reply(status_code, reason_phrase, extraHeaders);
    }

    var contentType = request.getHeader('Content-Type');
    var data = {'request': request, 'callback': null, 'reject': reject};

    sendAnswer(sdp) {
      var extraHeaders = ['Contact: ${this._contact}'];
      this._handleSessionTimersInIncomingRequest(request, extraHeaders);
      request.reply(200, null, extraHeaders, sdp);
      // If callback is given execute it.
      if (data['callback'] is Function) {
        data['callback']();
      }
    }

    // Emit 'update'.
    this.emit('update', data);

    if (rejected) {
      return;
    }

    if (request.body == null || request.body.length == 0) {
      sendAnswer(null);
      return;
    }

    if (contentType != 'application/sdp') {
      debug('invalid Content-Type');

      request.reply(415);

      return;
    }

    try {
      var desc = await this._processInDialogSdpOffer(request);
      if (this._status == C.STATUS_TERMINATED) return;
      // Send answer.
      sendAnswer(desc.sdp);
    } catch (error) {
      debugerror(error);
    }
  }

  _processInDialogSdpOffer(request) async {
    debug('_processInDialogSdpOffer()');

    var sdp = request.parseSDP();

    var hold = false;

    for (var m in sdp['media']) {
      if (holdMediaTypes.indexOf(m['type']) == -1) {
        continue;
      }

      var direction = m['direction'] ?? sdp['direction'] ?? 'sendrecv';

      if (direction == 'sendonly' || direction == 'inactive') {
        hold = true;
      }
      // If at least one of the streams is active don't emit 'hold'.
      else {
        hold = false;
        break;
      }
    }

    var e = {'originator': 'remote', 'type': 'offer', 'sdp': request.body};

    debug('emit "sdp"');
    this.emit('sdp', e);

    var offer = new RTCSessionDescription(request.body, 'offer');

    if (this._status == C.STATUS_TERMINATED) {
      throw new Exceptions.InvalidStateError('terminated');
    }
    try {
      await this._connection.setRemoteDescription(offer);
    } catch (error) {
      request.reply(488);
      debugerror(
          'emit "peerconnection:setremotedescriptionfailed" [error:${error.toString()}]');

      this.emit('peerconnection:setremotedescriptionfailed', error);

      throw new Exceptions.TypeError(
          'peerconnection.setRemoteDescription() failed');
    }

    if (this._status == C.STATUS_TERMINATED) {
      throw new Exceptions.InvalidStateError('terminated');
    }

    if (this._remoteHold == true && hold == false) {
      this._remoteHold = false;
      this._onunhold('remote');
    } else if (this._remoteHold == false && hold == true) {
      this._remoteHold = true;
      this._onhold('remote');
    }

    // Create local description.

    if (this._status == C.STATUS_TERMINATED) {
      throw new Exceptions.InvalidStateError('terminated');
    }

    try {
      return await this
          ._createLocalDescription('answer', this._rtcAnswerConstraints);
    } catch (_) {
      request.reply(500);
      throw new Exceptions.TypeError('_createLocalDescription() failed');
    }
  }

  /**
   * In dialog Refer Reception
   */
  _receiveRefer(request) {
    debug('receiveRefer()');

    if (request.refer_to == null) {
      debug('no Refer-To header field present in REFER');
      request.reply(400);

      return;
    }

    if (request.refer_to.uri.scheme != DartSIP_C.SIP) {
      debug('Refer-To header field points to a non-SIP URI scheme');
      request.reply(416);
      return;
    }

    // Reply before the transaction timer expires.
    request.reply(202);

    var notifier =
        new RTCSession_ReferNotifier.ReferNotifier(this, request.cseq);

    var accept = (initCallback, options) {
      initCallback = (initCallback is Function) ? initCallback : null;

      if (this._status != C.STATUS_WAITING_FOR_ACK &&
          this._status != C.STATUS_CONFIRMED) {
        return false;
      }

      RTCSession session = new RTCSession(this._ua);

      session.on('progress', ({response}) {
        notifier.notify(response.status_code, response.reason_phrase);
      });

      session.on('accepted', ({response}) {
        notifier.notify(response.status_code, response.reason_phrase);
      });

      session.on('_failed', ({message, cause}) {
        if (message != null) {
          notifier.notify(message.status_code, message.reason_phrase);
        } else {
          notifier.notify(487, cause);
        }
      });
      // Consider the Replaces header present in the Refer-To URI.
      if (request.refer_to.uri.hasHeader('replaces')) {
        var replaces = Utils.decodeURIComponent(
            request.refer_to.uri.getHeader('replaces'));

        options['extraHeaders'] = Utils.cloneArray(options['extraHeaders']);
        options['extraHeaders'].add('Replaces: ${replaces}');
      }
      session.connect(request.refer_to.uri.toAor(), options, initCallback);
    };

    var reject = () {
      notifier.notify(603);
    };

    debug('emit "refer"');

    // Emit 'refer'.
    this.emit('refer', {
      'request': request,
      'accept': (initCallback, options) {
        accept(initCallback, options);
      },
      'reject': () {
        reject();
      }
    });
  }

  /**
   * In dialog Notify Reception
   */
  _receiveNotify(request) {
    debug('receiveNotify()');

    if (request.event == null) {
      request.reply(400);
    }

    switch (request.event.event) {
      case 'refer':
        {
          var id;
          var referSubscriber;

          if (request.event.params && request.event.params.id) {
            id = request.event.params.id;
            referSubscriber = this._referSubscribers[id];
          } else if (this._referSubscribers.length == 1) {
            referSubscriber =
                this._referSubscribers[this._referSubscribers.keys.toList()[0]];
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
  _receiveReplaces(request) {
    debug('receiveReplaces()');

    accept(initCallback) {
      if (this._status != C.STATUS_WAITING_FOR_ACK &&
          this._status != C.STATUS_CONFIRMED) {
        return false;
      }

      RTCSession session = new RTCSession(this._ua);

      // Terminate the current session when the new one is confirmed.
      session.on('confirmed', () {
        this.terminate();
      });

      session.init_incoming(request, initCallback);
    }

    reject() {
      debug('Replaced INVITE rejected by the user');
      request.reply(486);
    }

    // Emit 'replace'.
    this.emit('replaces', {
      'request': request,
      'accept': (initCallback) {
        accept(initCallback);
      },
      'reject': () {
        reject();
      }
    });
  }

  /**
   * Initial Request Sender
   */
  Future<Null> _sendInitialRequest(
      mediaConstraints, rtcOfferConstraints, mediaStream) async {
    var request_sender = new RequestSender(this._ua, this._request, {
      'onRequestTimeout': () {
        this.onRequestTimeout();
      },
      'onTransportError': () {
        this.onTransportError();
      },
      // Update the request on authentication.
      'onAuthenticated': (request) {
        this._request = request;
      },
      'onReceiveResponse': (response) {
        this._receiveInviteResponse(response);
      }
    });

    // This Promise is resolved within the next iteration, so the app has now
    // a chance to set events such as 'peerconnection' and 'connecting'.
    var stream;
    // A stream is given, var the app set events such as 'peerconnection' and 'connecting'.
    if (mediaStream != null) {
      stream = mediaStream;
    } // Request for user media access.
    else if (mediaConstraints['audio'] != null ||
        mediaConstraints['video'] != null) {
      this._localMediaStreamLocallyGenerated = true;
      try {
        stream = await navigator.getUserMedia(mediaConstraints);
        var e = {'originator': 'local', 'stream': stream};
        this.emit('stream', e);
      } catch (error) {
        if (this._status == C.STATUS_TERMINATED) {
          throw new Exceptions.InvalidStateError('terminated');
        }
        this._failed('local', null, DartSIP_C.causes.USER_DENIED_MEDIA_ACCESS);
        debugerror('emit "getusermediafailed" [error:${error.toString()}]');
        this.emit('getusermediafailed', error);
        throw error;
      }
    }

    if (this._status == C.STATUS_TERMINATED) {
      throw new Exceptions.InvalidStateError('terminated');
    }

    this._localMediaStream = stream;

    if (stream != null) {
      this._connection.addStream(stream);
    }

    // TODO: should this be triggered here?
    this._connecting(this._request);
    try {
      var desc =
          await this._createLocalDescription('offer', rtcOfferConstraints);
      if (this._is_canceled || this._status == C.STATUS_TERMINATED) {
        throw new Exceptions.InvalidStateError('terminated');
      }

      this._request.body = desc.sdp;
      this._status = C.STATUS_INVITE_SENT;

      debug('emit "sending" [request]');

      // Emit 'sending' so the app can mangle the body before the request is sent.
      this.emit('sending', {'request': this._request});

      request_sender.send();
    } catch (error, s) {
      print("$error $s");
      this._failed('local', null, DartSIP_C.causes.WEBRTC_ERROR);
      if (this._status == C.STATUS_TERMINATED) {
        return;
      }
      debugerror(error);
      throw error;
    }
  }

  /// Reception of Response for Initial INVITE
  _receiveInviteResponse(response) async {
    debug('receiveInviteResponse()');

    /// Handle 2XX retransmissions and responses from forked requests.
    if (this._dialog != null &&
        (response.status_code >= 200 && response.status_code <= 299)) {
      ///
      /// If it is a retransmission from the endpoint that established
      /// the dialog, send an ACK
      ///
      if (this._dialog.id.call_id == response.call_id &&
          this._dialog.id.local_tag == response.from_tag &&
          this._dialog.id.remote_tag == response.to_tag) {
        this.sendRequest(SipMethod.ACK);
        return;
      } else {
        // If not, send an ACK  and terminate.
        try {
          Dialog dialog = new Dialog(this, response, 'UAC');
        } catch (error) {
          debug(error);
          return;
        }
        this.sendRequest(SipMethod.ACK);
        this.sendRequest(SipMethod.BYE);
        return;
      }
    }

    // Proceed to cancellation if the user requested.
    if (this._is_canceled) {
      if (response.status_code >= 100 && response.status_code < 200) {
        this._request.cancel(this._cancel_reason);
      } else if (response.status_code >= 200 && response.status_code < 299) {
        this._acceptAndTerminate(response);
      }
      return;
    }

    if (this._status != C.STATUS_INVITE_SENT &&
        this._status != C.STATUS_1XX_RECEIVED) {
      return;
    }

    var status_code = response.status_code.toString();

    if (Utils.test100(status_code)) {
      // 100 trying
      this._status = C.STATUS_1XX_RECEIVED;
    } else if (Utils.test1XX(status_code)) {
      // 1XX
      // Do nothing with 1xx responses without To tag.
      if (response.to_tag == null) {
        debug('1xx response received without to tag');
        return;
      }

      // Create Early Dialog if 1XX comes with contact.
      if (response.hasHeader('contact')) {
        // An error on dialog creation will fire 'failed' event.
        if (!this._createDialog(response, 'UAC', true)) {
          return;
        }
      }

      this._status = C.STATUS_1XX_RECEIVED;
      this._progress('remote', response);

      if (response.body == null || response.body.length == 0) {
        return;
      }

      var e = {'originator': 'remote', 'type': 'answer', 'sdp': response.body};

      debug('emit "sdp"');
      this.emit('sdp', e);

      var answer = new RTCSessionDescription(response.body, 'answer');

      try {
        this._connection.setRemoteDescription(answer);
      } catch (error) {
        debugerror(
            'emit "peerconnection:setremotedescriptionfailed" [error:${error.toString()}]');
        this.emit('peerconnection:setremotedescriptionfailed', error);
      }
    } else if (Utils.test2XX(status_code)) {
      // 2XX
      this._status = C.STATUS_CONFIRMED;

      if (response.body == null || response.body.length == 0) {
        this._acceptAndTerminate(response, 400, DartSIP_C.causes.MISSING_SDP);
        this._failed(
            'remote', response, DartSIP_C.causes.BAD_MEDIA_DESCRIPTION);
        return;
      }

      // An error on dialog creation will fire 'failed' event.
      if (this._createDialog(response, 'UAC') == null) {
        return;
      }

      var e = {'originator': 'remote', 'type': 'answer', 'sdp': response.body};

      debug('emit "sdp"');
      this.emit('sdp', e);

      var answer = new RTCSessionDescription(response.body, 'answer');

      // Be ready for 200 with SDP after a 180/183 with SDP.
      // We created a SDP 'answer' for it, so check the current signaling state.
      if (this._connection.signalingState ==
              RTCSignalingState.RTCSignalingStateStable ||
          this._connection.signalingState ==
              RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        try {
          var offer =
              await this._connection.createOffer(this._rtcOfferConstraints);
          await this._connection.setLocalDescription(offer);
        } catch (error) {
          this._acceptAndTerminate(response, 500, error.toString());
          this._failed('local', response, DartSIP_C.causes.WEBRTC_ERROR);
        }
      }

      try {
        await this._connection.setRemoteDescription(answer);

        // Handle Session Timers.
        this._handleSessionTimersInIncomingResponse(response);
        this._accepted('remote', response);
        this.sendRequest(SipMethod.ACK);
        this._confirmed('local', null);
      } catch (error) {
        this._acceptAndTerminate(response, 488, 'Not Acceptable Here');
        this._failed(
            'remote', response, DartSIP_C.causes.BAD_MEDIA_DESCRIPTION);
        debugerror(
            'emit "peerconnection:setremotedescriptionfailed" [error:${error.toString()}]');
        this.emit('peerconnection:setremotedescriptionfailed', error);
      }
    } else {
      var cause = Utils.sipErrorCause(response.status_code);
      this._failed('remote', response, cause);
    }
  }

  /**
   * Send Re-INVITE
   */
  _sendReinvite([options]) async {
    debug('sendReinvite()');

    var extraHeaders = Utils.cloneArray(options['extraHeaders']);
    var eventHandlers = options['eventHandlers'] ?? {};
    var rtcOfferConstraints =
        options['rtcOfferConstraints'] ?? this._rtcOfferConstraints || null;

    var succeeded = false;

    extraHeaders.add('Contact: ${this._contact}');
    extraHeaders.add('Content-Type: application/sdp');

    // Session Timers.
    if (this._sessionTimers.running) {
      extraHeaders.add(
          'Session-Expires: ${this._sessionTimers.currentExpires};refresher=${this._sessionTimers.refresher ? 'uac' : 'uas'}');
    }

    onFailed([response]) {
      if (eventHandlers['failed'] != null) {
        eventHandlers['failed'](response);
      }
    }

    onSucceeded(response) async {
      if (this._status == C.STATUS_TERMINATED) {
        return;
      }

      this.sendRequest(SipMethod.ACK);

      // If it is a 2XX retransmission exit now.
      if (succeeded != null) {
        return;
      }

      // Handle Session Timers.
      this._handleSessionTimersInIncomingResponse(response);

      // Must have SDP answer.
      if (!response.body) {
        onFailed();
        return;
      } else if (response.getHeader('Content-Type') != 'application/sdp') {
        onFailed();
        return;
      }

      var e = {'originator': 'remote', 'type': 'answer', 'sdp': response.body};

      debug('emit "sdp"');
      this.emit('sdp', e);

      var answer = new RTCSessionDescription(response.body, 'answer');

      try {
        await this._connection.setRemoteDescription(answer);
        if (eventHandlers['succeeded'] != null) {
          eventHandlers['succeeded'](response);
        }
      } catch (error) {
        onFailed();
        debugerror(
            'emit "peerconnection:setremotedescriptionfailed" [error:${error.toString()}]');
        this.emit('peerconnection:setremotedescriptionfailed', error);
      }
    }

    try {
      var desc =
          await this._createLocalDescription('offer', rtcOfferConstraints);
      var sdp = this._mangleOffer(desc.sdp);
      var e = {'originator': 'local', 'type': 'offer', 'sdp': sdp};
      debug('emit "sdp"');
      this.emit('sdp', e);

      this.sendRequest(SipMethod.INVITE, {
        'extraHeaders': extraHeaders,
        'body': sdp,
        'eventHandlers': {
          'onSuccessResponse': (response) {
            onSucceeded(response);
            succeeded = true;
          },
          'onErrorResponse': (response) {
            onFailed(response);
          },
          'onTransportError': () {
            this.onTransportError(); // Do nothing because session ends.
          },
          'onRequestTimeout': () {
            this.onRequestTimeout(); // Do nothing because session ends.
          },
          'onDialogError': () {
            this.onDialogError(); // Do nothing because session ends.
          }
        }
      });
    } catch (error) {
      onFailed(error);
    }
  }

  /**
   * Send UPDATE
   */
  _sendUpdate([options]) async {
    debug('sendUpdate()');

    options = options ?? {};

    var extraHeaders = Utils.cloneArray(options['extraHeaders'] ?? []);
    var eventHandlers = options['eventHandlers'] ?? {};
    var rtcOfferConstraints =
        options['rtcOfferConstraints'] ?? this._rtcOfferConstraints ?? {};
    var sdpOffer = options['sdpOffer'] ?? false;

    var succeeded = false;

    extraHeaders.add('Contact: ${this._contact}');

    // Session Timers.
    if (this._sessionTimers.running) {
      extraHeaders.add(
          'Session-Expires: ${this._sessionTimers.currentExpires};refresher=${this._sessionTimers.refresher ? 'uac' : 'uas'}');
    }

    onFailed([response]) {
      if (eventHandlers['failed'] != null) {
        eventHandlers['failed'](response);
      }
    }

    onSucceeded(IncomingResponse response) async {
      if (this._status == C.STATUS_TERMINATED) {
        return;
      }

      // Handle Session Timers.
      this._handleSessionTimersInIncomingResponse(response);

      // If it is a 2XX retransmission exit now.
      if (succeeded != null) {
        return;
      }

      // Must have SDP answer.
      if (sdpOffer != null) {
        if (response.body != null && response.body.trim().isNotEmpty) {
          onFailed();
          return;
        } else if (response.getHeader('Content-Type') != 'application/sdp') {
          onFailed();
          return;
        }

        var e = {
          'originator': 'remote',
          'type': 'answer',
          'sdp': response.body
        };

        debug('emit "sdp"');
        this.emit('sdp', e);

        var answer = new RTCSessionDescription(response.body, 'answer');

        try {
          await this._connection.setRemoteDescription(answer);
          if (eventHandlers['succeeded'] != null) {
            eventHandlers['succeeded'](response);
          }
        } catch (error) {
          onFailed(error);
          debugerror(
              'emit "peerconnection:setremotedescriptionfailed" [error:${error.toString()}]');
          this.emit('peerconnection:setremotedescriptionfailed', error);
        }
      }
      // No SDP answer.
      else if (eventHandlers['succeeded'] != null) {
        eventHandlers['succeeded'](response);
      }
    }

    if (sdpOffer) {
      extraHeaders.add('Content-Type: application/sdp');
      try {
        RTCSessionDescription desc =
            await this._createLocalDescription('offer', rtcOfferConstraints);
        String sdp = this._mangleOffer(desc.sdp);

        Map<String, String> e = {
          'originator': 'local',
          'type': 'offer',
          'sdp': sdp
        };

        debug('emit "sdp"');
        this.emit('sdp', e);

        this.sendRequest(SipMethod.UPDATE, {
          'extraHeaders': extraHeaders,
          'body': sdp,
          'eventHandlers': {
            'onSuccessResponse': (response) {
              onSucceeded(response);
              succeeded = true;
            },
            'onErrorResponse': (response) {
              onFailed(response);
            },
            'onTransportError': () {
              this.onTransportError(); // Do nothing because session ends.
            },
            'onRequestTimeout': () {
              this.onRequestTimeout(); // Do nothing because session ends.
            },
            'onDialogError': () {
              this.onDialogError(); // Do nothing because session ends.
            }
          }
        });
      } catch (error) {
        onFailed(error);
      }
    } else {
      // No SDP.
      this.sendRequest(SipMethod.UPDATE, {
        'extraHeaders': extraHeaders,
        'eventHandlers': {
          'onSuccessResponse': (response) {
            onSucceeded(response);
          },
          'onErrorResponse': (response) {
            onFailed(response);
          },
          'onTransportError': () {
            this.onTransportError(); // Do nothing because session ends.
          },
          'onRequestTimeout': () {
            this.onRequestTimeout(); // Do nothing because session ends.
          },
          'onDialogError': () {
            this.onDialogError(); // Do nothing because session ends.
          }
        }
      });
    }
  }

  _acceptAndTerminate(response, [status_code, reason_phrase]) async {
    debug('acceptAndTerminate()');

    var extraHeaders = [];

    if (status_code != null) {
      reason_phrase =
          reason_phrase ?? DartSIP_C.REASON_PHRASE[status_code] ?? '';
      extraHeaders
          .add('Reason: SIP ;cause=${status_code}; text="${reason_phrase}"');
    }

    // An error on dialog creation will fire 'failed' event.
    if (this._dialog != null || this._createDialog(response, 'UAC')) {
      this.sendRequest(SipMethod.ACK);
      this.sendRequest(SipMethod.BYE, {'extraHeaders': extraHeaders});
    }

    // Update session status.
    this._status = C.STATUS_TERMINATED;
  }

  /**
   * Correctly set the SDP direction attributes if the call is on local hold
   */
  String _mangleOffer(String sdpInput) {
    if (!this._localHold && !this._remoteHold) {
      return sdpInput;
    }

    Map<String, dynamic> sdp = sdp_transform.parse(sdpInput);

    // Local hold.
    if (this._localHold && !this._remoteHold) {
      debug('mangleOffer() | me on hold, mangling offer');
      for (var m in sdp['media']) {
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
    else if (this._localHold && this._remoteHold) {
      debug('mangleOffer() | both on hold, mangling offer');
      for (var m in sdp['media']) {
        if (holdMediaTypes.indexOf(m['type']) == -1) {
          continue;
        }
        m['direction'] = 'inactive';
      }
    }
    // Remote hold.
    else if (this._remoteHold) {
      debug('mangleOffer() | remote on hold, mangling offer');
      for (var m in sdp['media']) {
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

  _setLocalMediaStatus() {
    var enableAudio = true, enableVideo = true;

    if (this._localHold || this._remoteHold) {
      enableAudio = false;
      enableVideo = false;
    }

    if (this._audioMuted) {
      enableAudio = false;
    }

    if (this._videoMuted) {
      enableVideo = false;
    }

    this._toggleMuteAudio(!enableAudio);
    this._toggleMuteVideo(!enableVideo);
  }

  /**
   * Handle SessionTimers for an incoming INVITE or UPDATE.
   * @param  {IncomingRequest} request
   * @param  {Array} responseExtraHeaders  Extra headers for the 200 response.
   */
  _handleSessionTimersInIncomingRequest(request, responseExtraHeaders) {
    if (!this._sessionTimers.enabled) {
      return;
    }

    var session_expires_refresher;

    if (request.session_expires > 0 &&
        request.session_expires >= DartSIP_C.MIN_SESSION_EXPIRES) {
      this._sessionTimers.currentExpires = request.session_expires;
      session_expires_refresher = request.session_expires_refresher ?? 'uas';
    } else {
      this._sessionTimers.currentExpires = this._sessionTimers.defaultExpires;
      session_expires_refresher = 'uas';
    }

    responseExtraHeaders.add(
        'Session-Expires: ${this._sessionTimers.currentExpires};refresher=${session_expires_refresher}');

    this._sessionTimers.refresher = (session_expires_refresher == 'uas');
    this._runSessionTimer();
  }

  /**
   * Handle SessionTimers for an incoming response to INVITE or UPDATE.
   * @param  {IncomingResponse} response
   */
  _handleSessionTimersInIncomingResponse(response) {
    if (!this._sessionTimers.enabled) {
      return;
    }

    var session_expires_refresher;

    if (response.session_expires != 0 &&
        response.session_expires >= DartSIP_C.MIN_SESSION_EXPIRES) {
      this._sessionTimers.currentExpires = response.session_expires;
      session_expires_refresher = response.session_expires_refresher ?? 'uac';
    } else {
      this._sessionTimers.currentExpires = this._sessionTimers.defaultExpires;
      session_expires_refresher = 'uac';
    }

    this._sessionTimers.refresher = (session_expires_refresher == 'uac');
    this._runSessionTimer();
  }

  _runSessionTimer() {
    var expires = this._sessionTimers.currentExpires;

    this._sessionTimers.running = true;

    clearTimeout(this._sessionTimers.timer);

    // I'm the refresher.
    if (this._sessionTimers.refresher) {
      this._sessionTimers.timer = setTimeout(() {
        if (this._status == C.STATUS_TERMINATED) {
          return;
        }

        debug('runSessionTimer() | sending session refresh request');

        if (this._sessionTimers.refreshMethod == SipMethod.UPDATE) {
          this._sendUpdate();
        } else {
          this._sendReinvite();
        }
      }, expires * 500); // Half the given interval (as the RFC states).
    }
    // I'm not the refresher.
    else {
      this._sessionTimers.timer = setTimeout(() {
        if (this._status == C.STATUS_TERMINATED) {
          return;
        }

        debugerror(
            'runSessionTimer() | timer expired, terminating the session');

        this.terminate({
          'cause': DartSIP_C.causes.REQUEST_TIMEOUT,
          'status_code': 408,
          'reason_phrase': 'Session Timer Expired'
        });
      }, expires * 1100);
    }
  }

  _toggleMuteAudio(mute) {
    List<MediaStream> streams = this._connection.getLocalStreams();
    streams.forEach((stream) {
      if (stream.getAudioTracks().length > 0) {
        var track = stream.getAudioTracks()[0];
        track.enabled = !mute;
      }
    });
  }

  _toggleMuteVideo(mute) {
    List<MediaStream> streams = this._connection.getLocalStreams();
    streams.forEach((stream) {
      if (stream.getVideoTracks().length > 0) {
        var track = stream.getVideoTracks()[0];
        track.enabled = !mute;
      }
    });
  }

  _newRTCSession(originator, request) {
    debug('newRTCSession()');
    this._ua.newRTCSession(
        this, {'originator': originator, 'session': this, 'request': request});
  }

  _connecting(request) {
    debug('session connecting');
    debug('emit "connecting"');
    this.emit('connecting', {'request': request});
  }

  _progress(originator, response) {
    debug('session progress');
    debug('emit "progress"');
    this.emit(
        'progress', {'originator': originator, 'response': response ?? null});
  }

  _accepted(originator, [message]) {
    debug('session accepted');
    this._start_time = new DateTime.now();
    debug('emit "accepted"');
    this.emit(
        'accepted', {'originator': originator, 'response': message ?? null});
  }

  _confirmed(originator, ack) {
    debug('session confirmed');
    this._is_confirmed = true;
    debug('emit "confirmed"');
    this.emit('confirmed', {'originator': originator, 'ack': ack ?? null});
  }

  _ended(originator, message, cause) {
    debug('session ended');
    this._end_time = new DateTime.now();
    this._close();
    debug('emit "ended"');
    this.emit('ended',
        {'originator': originator, 'message': message ?? null, 'cause': cause});
  }

  _failed(originator, message, cause) {
    debug('session failed');

    // Emit private '_failed' event first.
    debug('emit "_failed"');

    this.emit('_failed', {
      'originator': originator,
      'message': message ?? null,
      'cause': cause,
    });

    this._close();
    debug('emit "failed"');
    this.emit('failed',
        {'originator': originator, 'message': message ?? null, 'cause': cause});
  }

  _onhold(originator) {
    debug('session onhold');
    this._setLocalMediaStatus();
    debug('emit "hold"');
    this.emit('hold', {'originator': originator});
  }

  _onunhold(originator) {
    debug('session onunhold');
    this._setLocalMediaStatus();
    debug('emit "unhold"');
    this.emit('unhold', {'originator': originator});
  }

  _onmute([audio, video]) {
    debug('session onmute');
    this._setLocalMediaStatus();
    debug('emit "muted"');
    this.emit('muted', {'audio': audio, 'video': video});
  }

  _onunmute([audio, video]) {
    debug('session onunmute');
    this._setLocalMediaStatus();
    debug('emit "unmuted"');
    this.emit('unmuted', {'audio': audio, 'video': video});
  }
}
