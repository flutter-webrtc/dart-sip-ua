import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';
import 'package:sdp_transform/sdp_transform.dart' as sdp_transform;
import 'package:sip_ua/sip_ua.dart';
import 'package:sip_ua/src/event_manager/internal_events.dart';
import 'package:sip_ua/src/map_helper.dart';
import 'package:sip_ua/src/transports/socket_interface.dart';
import 'package:sip_ua/src/transports/tcp_socket.dart';
import 'config.dart';
import 'constants.dart' as DartSIP_C;
import 'event_manager/event_manager.dart';
import 'event_manager/subscriber_events.dart';
import 'logger.dart';
import 'message.dart';
import 'rtc_session.dart';
import 'rtc_session/refer_subscriber.dart';
import 'sip_message.dart';
import 'stack_trace_nj.dart';
import 'subscriber.dart';
import 'transports/web_socket.dart';
import 'ua.dart';

class SIPUAHelper extends EventManager {
  SIPUAHelper({Logger? customLogger}) {
    if (customLogger != null) {
      logger = customLogger;
    }
  }

  UA? _ua;
  Settings _settings = Settings();
  UaSettings? _uaSettings;
  final Map<String?, Call> _calls = <String?, Call>{};

  RegistrationState _registerState =
      RegistrationState(state: RegistrationStateEnum.NONE);

  /// Sets the logging level for the default logger. Has no effect if custom logger is supplied.
  set loggingLevel(Level loggingLevel) => Log.loggingLevel = loggingLevel;

  bool get registered {
    if (_ua != null) {
      return _ua!.isRegistered();
    }
    return false;
  }

  bool get connected {
    if (_ua != null) {
      return _ua!.isConnected();
    }
    return false;
  }

  bool get connecting {
    if (_ua == null) return false;

    if (_ua!.socketTransport != null)
      return _ua!.socketTransport!.isConnecting();

    return false;
  }

  RegistrationState get registerState => _registerState;

  void stop() async {
    if (_ua != null) {
      _ua!.stop();
    } else {
      logger.w('ERROR: stop called but not started, call start first.');
    }
  }

  void register() {
    assert(_ua != null,
        'register called but not started, you must call start first.');
    _ua!.register();
  }

  void unregister([bool all = true]) {
    if (_ua != null) {
      assert(registered, 'ERROR: you must call register first.');
      _ua!.unregister(all: all);
    } else {
      logger.e('ERROR: unregister called, you must call start first.');
    }
  }

  Future<bool> call(String target,
      {bool voiceOnly = false,
      MediaStream? mediaStream,
      List<String>? headers,
      Map<String, dynamic>? customOptions}) async {
    if (_ua != null && _ua!.isConnected()) {
      Map<String, dynamic> options = buildCallOptions(voiceOnly);

      if (customOptions != null) {
        options = MapHelper.merge(options, customOptions);
      }
      if (mediaStream != null) {
        options['mediaStream'] = mediaStream;
      }
      List<dynamic> extHeaders = options['extraHeaders'] as List<dynamic>;
      extHeaders.addAll(headers ?? <String>[]);
      options['extraHeaders'] = extHeaders;
      _ua!.call(target, options);
      return true;
    } else {
      logger.e('Not connected, you will need to register.',
          stackTrace: StackTraceNJ());
    }
    return false;
  }

  Call? findCall(String id) {
    return _calls[id];
  }

  Future<void> renegotiate({
    required Call call,
    required bool voiceOnly,
    Map<String, dynamic>? options,
    bool useUpdate = false,
    Function(IncomingMessage)? done,
  }) async {
    Map<String, dynamic> finalOptions = options ?? buildCallOptions(voiceOnly);
    call.renegotiate(options: finalOptions, useUpdate: useUpdate, done: done);
  }

  Future<void> start(UaSettings uaSettings) async {
    if (_ua != null) {
      logger.w('UA instance already exist!, stopping UA and creating a one...');
      _ua!.stop();
    }

    _uaSettings = uaSettings;

    // Reset settings
    _settings = Settings();

    _settings.sockets = <SIPUASocketInterface>[];

    if (uaSettings.transportType == TransportType.TCP) {
      SIPUATcpSocket socket = SIPUATcpSocket(
          uaSettings.host ?? '0.0.0.0', uaSettings.port ?? '5060',
          messageDelay: 1);
      _settings.sockets!.add(socket);
    }

    if (uaSettings.transportType == TransportType.WS) {
      SIPUAWebSocket socket = SIPUAWebSocket(
          uaSettings.webSocketUrl ?? 'wss://tryit.jssip.net:10443',
          messageDelay: _settings.sip_message_delay,
          webSocketSettings: uaSettings.webSocketSettings);
      _settings.sockets!.add(socket);
    }

    _settings.transportType = uaSettings.transportType!;
    _settings.uri = uaSettings.uri;
    _settings.sip_message_delay = uaSettings.sip_message_delay;
    _settings.realm = uaSettings.realm;
    _settings.password = uaSettings.password;
    _settings.ha1 = uaSettings.ha1;
    _settings.display_name = uaSettings.displayName;
    _settings.authorization_user = uaSettings.authorizationUser;
    _settings.user_agent = uaSettings.userAgent ?? DartSIP_C.USER_AGENT;
    _settings.register = uaSettings.register;
    _settings.register_expires = uaSettings.register_expires;
    _settings.register_extra_headers = uaSettings.registerParams.extraHeaders;
    _settings.register_extra_contact_uri_params =
        uaSettings.registerParams.extraContactUriParams;
    _settings.dtmf_mode = uaSettings.dtmfMode;
    _settings.session_timers = uaSettings.sessionTimers;
    _settings.ice_gathering_timeout = uaSettings.iceGatheringTimeout;
    _settings.session_timers_refresh_method =
        uaSettings.sessionTimersRefreshMethod;
    _settings.instance_id = uaSettings.instanceId;
    _settings.registrar_server = uaSettings.registrarServer;
    _settings.contact_uri = uaSettings.contact_uri;
    _settings.connection_recovery_max_interval = 
        uaSettings.connectionRecoveryMaxInterval;
    _settings.connection_recovery_min_interval = 
        uaSettings.connectionRecoveryMinInterval;
    _settings.terminateOnAudioMediaPortZero =
        uaSettings.terminateOnMediaPortZero;

    try {
      _ua = UA(_settings);
      _ua!.on(EventSocketConnecting(), (EventSocketConnecting event) {
        logger.d('connecting => $event');
        _notifyTransportStateListeners(
            TransportState(TransportStateEnum.CONNECTING));
      });

      _ua!.on(EventSocketConnected(), (EventSocketConnected event) {
        logger.d('connected => $event');
        _notifyTransportStateListeners(
            TransportState(TransportStateEnum.CONNECTED));
      });

      _ua!.on(EventSocketDisconnected(), (EventSocketDisconnected event) {
        logger.d('disconnected => ${event.cause}');
        _notifyTransportStateListeners(TransportState(
            TransportStateEnum.DISCONNECTED,
            cause: event.cause));
      });

      _ua!.on(EventRegistered(), (EventRegistered event) {
        logger.d('registered => ${event.cause}');
        _registerState = RegistrationState(
            state: RegistrationStateEnum.REGISTERED, cause: event.cause);
        _notifyRegistrationStateListeners(_registerState);
      });

      _ua!.on(EventUnregister(), (EventUnregister event) {
        logger.d('unregistered => ${event.cause}');
        _registerState = RegistrationState(
            state: RegistrationStateEnum.UNREGISTERED, cause: event.cause);
        _notifyRegistrationStateListeners(_registerState);
      });

      _ua!.on(EventRegistrationFailed(), (EventRegistrationFailed event) {
        logger.d('registrationFailed => ${event.cause}');
        _registerState = RegistrationState(
            state: RegistrationStateEnum.REGISTRATION_FAILED,
            cause: event.cause);
        _notifyRegistrationStateListeners(_registerState);
      });

      _ua!.on(EventNewRTCSession(), (EventNewRTCSession event) {
        logger.d('newRTCSession => $event');
        RTCSession session = event.session!;
        if (session.direction == 'incoming') {
          // Set event handlers.
          session.addAllEventHandlers(
              buildCallOptions()['eventHandlers'] as EventManager);
        }
        bool hasVideo = session.data?['video'] ?? false;

        _calls[event.id] =
            Call(event.id, session, CallStateEnum.CALL_INITIATION, !hasVideo);
        _notifyCallStateListeners(
            event,
            CallState(CallStateEnum.CALL_INITIATION,
                video: session.data?['video']));
      });

      _ua!.on(EventNewMessage(), (EventNewMessage event) {
        logger.d('newMessage => $event');
        //Only notify incoming message to listener
        if (event.message!.direction == 'incoming') {
          SIPMessageRequest message =
              SIPMessageRequest(event.message, event.originator, event.request);
          _notifyNewMessageListeners(message);
        }
      });

      _ua!.start();
    } catch (e, s) {
      logger.e(e.toString(), error: e, stackTrace: s);
    }
  }

  /// Build the call options.
  /// You may override this method in a custom SIPUAHelper class in order to
  /// modify the options to your needs.
  Map<String, dynamic> buildCallOptions([bool voiceonly = false]) =>
      _options(voiceonly);

  Map<String, dynamic> _options([bool voiceonly = false]) {
    // Register callbacks to desired call events
    EventManager handlers = EventManager();
    handlers.on(EventCallConnecting(), (EventCallConnecting event) {
      logger.d('call connecting');
      _notifyCallStateListeners(event, CallState(CallStateEnum.CONNECTING));
    });
    handlers.on(EventCallProgress(), (EventCallProgress event) {
      logger.d('call is in progress');
      _notifyCallStateListeners(
          event,
          CallState(CallStateEnum.PROGRESS,
              originator: event.originator, cause: event.cause));
    });
    handlers.on(EventCallFailed(), (EventCallFailed event) {
      logger.d('call failed with cause: ${event.cause}');
      _notifyCallStateListeners(
          event,
          CallState(CallStateEnum.FAILED,
              originator: event.originator, cause: event.cause));
      _calls.remove(event.id);
    });
    handlers.on(EventCallEnded(), (EventCallEnded event) {
      logger.d('call ended with cause: ${event.cause}');
      _notifyCallStateListeners(
          event,
          CallState(CallStateEnum.ENDED,
              originator: event.originator, cause: event.cause));
      _calls.remove(event.id);
    });
    handlers.on(EventCallAccepted(), (EventCallAccepted event) {
      logger.d('call accepted');
      _notifyCallStateListeners(event, CallState(CallStateEnum.ACCEPTED));
    });
    handlers.on(EventCallConfirmed(), (EventCallConfirmed event) {
      logger.d('call confirmed');
      _notifyCallStateListeners(event, CallState(CallStateEnum.CONFIRMED));
    });
    handlers.on(EventCallHold(), (EventCallHold event) {
      logger.d('call hold');
      _notifyCallStateListeners(
          event, CallState(CallStateEnum.HOLD, originator: event.originator));
    });
    handlers.on(EventCallUnhold(), (EventCallUnhold event) {
      logger.d('call unhold');
      _notifyCallStateListeners(
          event, CallState(CallStateEnum.UNHOLD, originator: event.originator));
    });
    handlers.on(EventCallMuted(), (EventCallMuted event) {
      logger.d('call muted');
      _notifyCallStateListeners(
          event,
          CallState(CallStateEnum.MUTED,
              audio: event.audio, video: event.video));
    });
    handlers.on(EventCallUnmuted(), (EventCallUnmuted event) {
      logger.d('call unmuted');
      _notifyCallStateListeners(
          event,
          CallState(CallStateEnum.UNMUTED,
              audio: event.audio, video: event.video));
    });
    handlers.on(EventStream(), (EventStream event) async {
      // Waiting for callscreen ready.
      Timer(Duration(milliseconds: 100), () {
        _notifyCallStateListeners(
            event,
            CallState(CallStateEnum.STREAM,
                stream: event.stream, originator: event.originator));
      });
    });

    handlers.on(EventReInvite(), (EventReInvite event) {
      logger.d('Reinvite received in helper, notifying listeners');
      _notifyReInviteListeners(event);
    });
    handlers.on(EventCallRefer(), (EventCallRefer refer) async {
      logger.d('Refer received, Transfer current call to => ${refer.aor}');
      _notifyCallStateListeners(
          refer, CallState(CallStateEnum.REFER, refer: refer));
      //Always accept.
      refer.accept((RTCSession session) {
        logger.d('session initialized.');
      }, buildCallOptions(true));
    });

    Map<String, dynamic> defaultOptions = <String, dynamic>{
      'eventHandlers': handlers,
      'extraHeaders': <dynamic>[],
      'pcConfig': <String, dynamic>{
        'sdpSemantics': 'unified-plan',
        'iceTransportPolicy':
            (_uaSettings?.iceTransportPolicy ?? IceTransportPolicy.ALL)
                .toParameterString(),
        'iceServers': _uaSettings?.iceServers
      },
      'mediaConstraints': <String, dynamic>{
        'audio': true,
        'video': voiceonly
            ? false
            : <String, dynamic>{
                'mandatory': <String, dynamic>{
                  'minWidth': '640',
                  'minHeight': '480',
                  'minFrameRate': '30',
                },
                'facingMode': 'user',
                'optional': <dynamic>[],
              }
      },
      'rtcOfferConstraints': <String, dynamic>{
        'mandatory': <String, dynamic>{
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': !voiceonly,
        },
        'optional': <dynamic>[],
      },
      'rtcAnswerConstraints': <String, dynamic>{
        'mandatory': <String, dynamic>{
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': !voiceonly,
        },
        'optional': <dynamic>[],
      },
      'rtcConstraints': <String, dynamic>{
        'mandatory': <dynamic, dynamic>{},
        'optional': <Map<String, dynamic>>[
          <String, dynamic>{'DtlsSrtpKeyAgreement': true},
        ],
      },
      'sessionTimersExpires': 120
    };
    return defaultOptions;
  }

  bool setUAParam(String parameter, dynamic value) {
    return _ua!.set(parameter, value);
  }

  Message sendMessage(String target, String body,
      [Map<String, dynamic>? options, Map<String, dynamic>? params]) {
    return _ua!.sendMessage(target, body, options, params);
  }

  void subscribe(String target, String event, String contentType) {
    Subscriber s = _ua!.subscribe(target, event, contentType);

    s.on(EventNotify(), (EventNotify event) {
      _notifyNotifyListeners(event);
    });

    s.subscribe();
  }

  void terminateSessions(Map<String, dynamic> options) {
    _ua!.terminateSessions(options);
  }

  final Set<SipUaHelperListener> _sipUaHelperListeners =
      <SipUaHelperListener>{};

  void addSipUaHelperListener(SipUaHelperListener listener) {
    _sipUaHelperListeners.add(listener);
  }

  void removeSipUaHelperListener(SipUaHelperListener listener) {
    _sipUaHelperListeners.remove(listener);
  }

  void _notifyTransportStateListeners(TransportState state) {
    // Copy to prevent concurrent modification exception
    List<SipUaHelperListener> listeners = _sipUaHelperListeners.toList();
    for (SipUaHelperListener listener in listeners) {
      listener.transportStateChanged(state);
    }
  }

  void _notifyRegistrationStateListeners(RegistrationState state) {
    // Copy to prevent concurrent modification exception
    List<SipUaHelperListener> listeners = _sipUaHelperListeners.toList();
    for (SipUaHelperListener listener in listeners) {
      listener.registrationStateChanged(state);
    }
  }

  void _notifyCallStateListeners(CallEvent event, CallState state) {
    Call? call = _calls[event.id];
    if (call == null) {
      logger.e('Call ${event.id} not found!');
      return;
    }
    call.state = state.state;
    // Copy to prevent concurrent modification exception
    List<SipUaHelperListener> listeners = _sipUaHelperListeners.toList();
    for (SipUaHelperListener listener in listeners) {
      listener.callStateChanged(call, state);
    }
  }

  void _notifyNewMessageListeners(SIPMessageRequest msg) {
    // Copy to prevent concurrent modification exception
    List<SipUaHelperListener> listeners = _sipUaHelperListeners.toList();
    for (SipUaHelperListener listener in listeners) {
      listener.onNewMessage(msg);
    }
  }

  void _notifyReInviteListeners(EventReInvite event) {
    // Copy to prevent concurrent modification exception
    List<SipUaHelperListener> listeners = _sipUaHelperListeners.toList();
    for (SipUaHelperListener listener in listeners) {
      IncomingRequest request = event.request as IncomingRequest;
      String body = request.body ?? '';
      if (request.sdp == null && body.isNotEmpty) {
        request.sdp = sdp_transform.parse(body);
      }
      listener.onNewReinvite(ReInvite(
          sdp: request.sdp,
          hasAudio: event.hasAudio,
          hasVideo: event.hasVideo,
          accept: event.callback,
          reject: event.reject));
    }
  }

  void _notifyNotifyListeners(EventNotify event) {
    // Copy to prevent concurrent modification exception
    List<SipUaHelperListener> listeners = _sipUaHelperListeners.toList();
    for (SipUaHelperListener listener in listeners) {
      listener.onNewNotify(Notify(request: event.request));
    }
  }
}

enum CallStateEnum {
  NONE,
  STREAM,
  UNMUTED,
  MUTED,
  CONNECTING,
  PROGRESS,
  FAILED,
  ENDED,
  ACCEPTED,
  CONFIRMED,
  REFER,
  HOLD,
  UNHOLD,
  CALL_INITIATION,
}

class Call {
  Call(this._id, this._session, this.state, this.voiceOnly);
  final String? _id;
  final RTCSession _session;

  String? get id => _id;
  RTCPeerConnection? get peerConnection => _session.connection;
  RTCSession get session => _session;
  CallStateEnum state;
  bool voiceOnly;

  void answer(Map<String, dynamic> options, {MediaStream? mediaStream = null}) {
    assert(_session != null, 'ERROR(answer): rtc session is invalid!');
    if (mediaStream != null) {
      options['mediaStream'] = mediaStream;
    }
    _session.answer(options);
  }

  void refer(String target) {
    assert(_session != null, 'ERROR(refer): rtc session is invalid!');
    ReferSubscriber refer = _session.refer(target)!;
    refer.on(EventReferTrying(), (EventReferTrying data) {});
    refer.on(EventReferProgress(), (EventReferProgress data) {});
    refer.on(EventReferAccepted(), (EventReferAccepted data) {
      _session.terminate();
    });
    refer.on(EventReferFailed(), (EventReferFailed data) {});
  }

  void hangup([Map<String, dynamic>? options]) {
    assert(_session != null, 'ERROR(hangup): rtc session is invalid!');
    if (peerConnection != null) {
      for (MediaStream? stream in peerConnection!.getLocalStreams()) {
        if (stream == null) return;
        logger.d(
            'Stopping local stream with tracks: ${stream.getTracks().length}');
        for (MediaStreamTrack track in stream.getTracks()) {
          logger.d('Stopping track: ${track.kind}${track.id} ');
          track.stop();
        }
      }
      for (MediaStream? stream in peerConnection!.getRemoteStreams()) {
        if (stream == null) return;
        logger.d(
            'Stopping remote stream with tracks: ${stream.getTracks().length}');
        for (MediaStreamTrack track in stream.getTracks()) {
          logger.d('Stopping track: ${track.kind}${track.id} ');
          track.stop();
        }
      }
    } else {
      logger.d("peerConnection is null, can't stop tracks.");
    }
    _session.terminate(options);
  }

  void hold() {
    assert(_session != null, 'ERROR(hold): rtc session is invalid!');
    _session.hold();
  }

  void unhold() {
    assert(_session != null, 'ERROR(unhold): rtc session is invalid!');
    _session.unhold();
  }

  void mute([bool audio = true, bool video = true]) {
    assert(_session != null, 'ERROR(mute): rtc session is invalid!');
    _session.mute(audio, video);
  }

  void unmute([bool audio = true, bool video = true]) {
    assert(_session != null, 'ERROR(unmute): rtc session is invalid!');
    _session.unmute(audio, video);
  }

  void renegotiate({
    required Map<String, dynamic>? options,
    bool useUpdate = false,
    Function(IncomingMessage)? done,
  }) {
    assert(_session != null, 'ERROR(renegotiate): rtc session is invalid!');
    _session.renegotiate(options: options, useUpdate: useUpdate, done: done);
  }

  void sendDTMF(String tones, [Map<String, dynamic>? options]) {
    assert(_session != null, 'ERROR(sendDTMF): rtc session is invalid!');
    _session.sendDTMF(tones, options);
  }

  void sendInfo(String contentType, String body, Map<String, dynamic> options) {
    assert(_session != null, 'ERROR(sendInfo): rtc session is invalid');
    _session.sendInfo(contentType, body, options);
  }

  void sendMessage(String body, [Map<String, dynamic>? options]) {
    assert(_session != null, 'ERROR(sendMessage): rtc session is invalid');

    options?.putIfAbsent('body', () => body);

    _session.sendRequest(DartSIP_C.SipMethod.MESSAGE,
        options ?? <String, dynamic>{'body': body});
  }

  String? get remote_display_name {
    assert(_session != null,
        'ERROR(get remote_identity): rtc session is invalid!');
    if (_session.remote_identity != null &&
        _session.remote_identity!.display_name != null) {
      return _session.remote_identity!.display_name;
    }
    return '';
  }

  String? get remote_identity {
    assert(_session != null,
        'ERROR(get remote_identity): rtc session is invalid!');
    if (_session.remote_identity != null &&
        _session.remote_identity!.uri != null &&
        _session.remote_identity!.uri!.user != null) {
      return _session.remote_identity!.uri!.user;
    }
    return '';
  }

  String? get local_identity {
    assert(
        _session != null, 'ERROR(get local_identity): rtc session is invalid!');
    if (_session.local_identity != null &&
        _session.local_identity!.uri != null &&
        _session.local_identity!.uri!.user != null) {
      return _session.local_identity!.uri!.user;
    }
    return '';
  }

  String get direction {
    assert(_session != null, 'ERROR(get direction): rtc session is invalid!');
    if (_session.direction != null) {
      return _session.direction!.toUpperCase();
    }
    return '';
  }

  bool get remote_has_audio => _peerHasMediaLine('audio');

  bool get remote_has_video => _peerHasMediaLine('video');

  bool _peerHasMediaLine(String media) {
    assert(
        _session != null, 'ERROR(_peerHasMediaLine): rtc session is invalid!');
    if (_session.request == null) {
      return false;
    }

    bool peerHasMediaLine = false;
    Map<String, dynamic> sdp = _session.request.parseSDP();
    // Make sure sdp['media'] is an array, not the case if there is only one media.
    if (sdp['media'] is! List) {
      sdp['media'] = <dynamic>[sdp['media']];
    }
    // Go through all medias in SDP to find offered capabilities to answer with.
    for (Map<String, dynamic> m in sdp['media']) {
      if (media == 'audio' && m['type'] == 'audio') {
        peerHasMediaLine = true;
      }
      if (media == 'video' && m['type'] == 'video') {
        peerHasMediaLine = true;
      }
    }
    return peerHasMediaLine;
  }

  Future<List<StatsReport>>? getStats([MediaStreamTrack? track]) {
    return peerConnection?.getStats(track);
  }
}

class CallState {
  CallState(this.state,
      {this.originator,
      this.audio,
      this.video,
      this.stream,
      this.cause,
      this.refer});
  CallStateEnum state;
  ErrorCause? cause;
  String? originator;
  bool? audio;
  bool? video;
  MediaStream? stream;
  EventCallRefer? refer;
}

enum RegistrationStateEnum {
  NONE,
  REGISTRATION_FAILED,
  REGISTERED,
  UNREGISTERED,
}

class RegistrationState {
  RegistrationState({this.state, this.cause});
  RegistrationStateEnum? state;
  ErrorCause? cause;
}

enum TransportStateEnum {
  NONE,
  CONNECTING,
  CONNECTED,
  DISCONNECTED,
}

class TransportState {
  TransportState(this.state, {this.cause});
  TransportStateEnum state;
  ErrorCause? cause;
}

class SIPMessageRequest {
  SIPMessageRequest(this.message, this.originator, this.request);
  dynamic request;
  String? originator;
  Message? message;
}

abstract class SipUaHelperListener {
  void transportStateChanged(TransportState state);
  void registrationStateChanged(RegistrationState state);
  void callStateChanged(Call call, CallState state);
  //For SIP message coming
  void onNewMessage(SIPMessageRequest msg);
  void onNewNotify(Notify ntf);
  void onNewReinvite(ReInvite event);
}

class Notify {
  Notify({this.request});
  IncomingRequest? request;
}

class ReInvite {
  ReInvite({this.hasVideo, this.hasAudio, this.sdp, this.accept, this.reject});
  bool? hasVideo;
  bool? hasAudio;
  Map<String, dynamic>? sdp;
  Future<bool> Function(Map<String, dynamic> options)? accept;
  bool Function(Map<String, dynamic> options)? reject;
}

class RegisterParams {
  /// Allow extra headers and Contact Params to be sent on REGISTER
  /// Mainly used for RFC8599 Support
  /// https://github.com/cloudwebrtc/dart-sip-ua/issues/89
  List<String> extraHeaders = <String>[];
  Map<String, dynamic> extraContactUriParams = <String, dynamic>{};
}

class WebSocketSettings {
  /// Add additional HTTP headers, such as:'Origin','Host' or others
  Map<String, dynamic> extraHeaders = <String, dynamic>{};

  /// `User Agent` field for dart http client.
  String? userAgent;

  /// Don‘t check the server certificate
  /// for self-signed certificate.
  bool allowBadCertificate = false;

  /// Custom transport scheme string to use.
  /// Otherwise the used protocol will be used (for example WS for ws://
  /// or WSS for wss://, based on the given web socket URL).
  String? transport_scheme;
}

class TcpSocketSettings {
  /// Add additional HTTP headers, such as:'Origin','Host' or others
  Map<String, dynamic> extraHeaders = <String, dynamic>{};

  /// `User Agent` field for dart http client.
  String? userAgent;

  /// Don‘t check the server certificate
  /// for self-signed certificate.
  bool allowBadCertificate = false;
}

enum DtmfMode {
  INFO,
  RFC2833,
}

/// Possible values for the transport policy to be used when selecting ICE
/// candidates.
///
/// See: https://udn.realityripple.com/docs/Web/API/RTCConfiguration
enum IceTransportPolicy {
  /// All ICE candidates will be considered.
  /// This is the default if not specified explicitly.
  ALL,

  /// Only ICE candidates whose IP addresses are being relayed, such as those
  /// being passed through a TURN server, will be considered.
  RELAY,
}

extension _IceTransportPolicyEncoding on IceTransportPolicy {
  String toParameterString() {
    switch (this) {
      case IceTransportPolicy.ALL:
        return 'all';
      case IceTransportPolicy.RELAY:
        return 'relay';
    }
  }
}

class UaSettings {
  WebSocketSettings webSocketSettings = WebSocketSettings();
  TcpSocketSettings tcpSocketSettings = TcpSocketSettings();

  /// May not need to register if on a static IP, just Auth
  /// Default is true
  bool? register;

  /// Default is 600 secs in config.dart
  int? register_expires;

  /// Mainly used for RFC8599 Push Notification Support
  RegisterParams registerParams = RegisterParams();

  /// `User Agent` field for sip message.
  String? userAgent;
  String? host;
  String? port;
  String? uri;
  String? webSocketUrl;
  String? realm;
  String? authorizationUser;
  String? password;
  String? ha1;
  String? displayName;
  String? instanceId;
  String? registrarServer;
  String? contact_uri;

  TransportType? transportType;

  /// DTMF mode, in band (rfc2833) or out of band (sip info)
  DtmfMode dtmfMode = DtmfMode.INFO;

  /// Session Timers
  bool sessionTimers = true;

  /// ICE Gathering Timeout, default 500ms
  int iceGatheringTimeout = 500;

  /// Max interval between recovery connection, default 30 sec
  int connectionRecoveryMaxInterval = 30;

  /// Min interval between recovery connection, default 2 sec
  int connectionRecoveryMinInterval = 2;

  bool terminateOnMediaPortZero = false;

  /// Sip Message Delay (in millisecond) (default 0).
  int sip_message_delay = 0;
  List<Map<String, String>> iceServers = <Map<String, String>>[
    <String, String>{'urls': 'stun:stun.l.google.com:19302'},
// turn server configuration example.
//    {
//      'url': 'turn:123.45.67.89:3478',
//      'username': 'change_to_real_user',
//      'credential': 'change_to_real_secret'
//    },
  ];

  /// Defines the transport policy to be used for ICE.
  /// See [IceTransportPolicy] for possible values.
  /// Will default to [IceTransportPolicy.ALL] if not specified.
  IceTransportPolicy? iceTransportPolicy;

  /// Controls which kind of messages are to be sent to keep a SIP session
  /// alive.
  /// Defaults to "UPDATE"
  DartSIP_C.SipMethod sessionTimersRefreshMethod = DartSIP_C.SipMethod.UPDATE;
}
