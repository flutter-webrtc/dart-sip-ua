import 'dart:async';
import 'package:flutter_webrtc/media_stream.dart';
import 'package:logger/logger.dart';

import 'Config.dart';
import 'Message.dart';
import 'RTCSession.dart';
import 'Socket.dart';
import 'UA.dart';
import 'WebSocketInterface.dart';
import 'logger.dart';
import 'event_manager/event_manager.dart';
import 'stack_trace_nj.dart';

class SIPUAHelper extends EventManager {
  UA _ua;
  Settings _settings;
  final Log logger = Log();
  RTCSession _session;
  RegistrationState _registerState =
      RegistrationState(state: RegistrationStateEnum.NONE);

  SIPUAHelper() {
    Log.loggingLevel = Level.debug;
  }

  set loggingLevel(Level loggingLevel) => Log.loggingLevel = loggingLevel;

  bool get registered {
    if (this._ua != null) {
      return this._ua.isRegistered();
    }
    return false;
  }

  bool get connected {
    if (this._ua != null) {
      return this._ua.isConnected();
    }
    return false;
  }

  RegistrationState get registerState => _registerState;

  String get remote_identity {
    if (_session != null && _session.remote_identity != null) {
      if (_session.remote_identity.display_name != null) {
        return _session.remote_identity.display_name;
      } else {
        if (_session.remote_identity.uri != null &&
            _session.remote_identity.uri.user != null) {
          return _session.remote_identity.uri.user;
        }
      }
    }
    return "";
  }

  String get direction {
    if (_session != null && _session.direction != null) {
      return _session.direction.toUpperCase();
    }
    return "";
  }

  void stop() async {
    if (this._ua != null) {
      await this._ua.stop();
    } else {
      Log.w("ERROR: stop called but not started, call start first.");
    }
  }

  void register() {
    assert(this._ua != null,
        "register called but not started, you must call start first.");
    this._ua.register();
  }

  void unregister([bool all = true]) {
    if (this._ua != null) {
      assert(!registered, "ERROR: you must call register first.");
      this._ua.unregister(all: all);
    } else {
      Log.e("ERROR: unregister called, you must call start first.");
    }
  }

  Future<RTCSession> call(String uri, [bool voiceonly = false]) async {
    if (_ua != null && _ua.isConnected()) {
      _session = _ua.call(uri, this._options(voiceonly));
      return _session;
    } else {
      logger.error(
          "Not connected, you will need to register.", null, StackTraceNJ());
    }
    return null;
  }

  void answer() {
    if (_session != null) {
      _session.answer(this._options());
    }
  }

  void hangup() {
    if (_session != null) {
      _session.terminate();
    }
  }

  void start(String wsUrl, String uri,
      [String password,
      String displayName,
      Map<String, dynamic> wsExtraHeaders]) async {
    if (this._ua != null) {
      logger.warn(
          'UA instance already exist!, stopping UA and creating a new one...');
      this._ua.stop();
    }
    _settings = Settings();
    var socket = WebSocketInterface(wsUrl, wsExtraHeaders);
    _settings.sockets = [socket];
    _settings.uri = uri;
    _settings.password = password;
    _settings.display_name = displayName;

    try {
      this._ua = UA(_settings);
      this._ua.on(EventSocketConnecting(), (EventSocketConnecting event) {
        logger.debug('connecting => ' + event.toString());
        _notifyTransportStateListeners(TransportState(
            TransportStateEnum.CONNECTING,
            socket: event.socket));
      });

      this._ua.on(EventSocketConnected(), (EventSocketConnected event) {
        logger.debug('connected => ' + event.toString());
        _notifyTransportStateListeners(
            TransportState(TransportStateEnum.CONNECTED, socket: event.socket));
      });

      this._ua.on(EventSocketDisconnected(), (EventSocketDisconnected event) {
        logger.debug('disconnected => ' + (event.cause.toString()));
        _notifyTransportStateListeners(TransportState(
            TransportStateEnum.DISCONNECTED,
            socket: event.socket,
            cause: event.cause));
      });

      this._ua.on(EventRegistered(), (EventRegistered event) {
        logger.debug('registered => ' + event.cause.toString());
        _registerState = RegistrationState(
            state: RegistrationStateEnum.REGISTERED, cause: event.cause);
        _notifyRegsistrationStateListeners(_registerState);
      });

      this._ua.on(EventUnregister(), (EventUnregister event) {
        logger.debug('unregistered => ' + event.cause.toString());
        _registerState = RegistrationState(
            state: RegistrationStateEnum.UNREGISTERED, cause: event.cause);
        _notifyRegsistrationStateListeners(_registerState);
      });

      this._ua.on(EventRegistrationFailed(), (EventRegistrationFailed event) {
        logger.debug('registrationFailed => ' + (event.cause.toString()));
        _registerState = RegistrationState(
            state: RegistrationStateEnum.REGISTRATION_FAILED,
            cause: event.cause);
        _notifyRegsistrationStateListeners(_registerState);
      });

      this._ua.on(EventNewRTCSession(), (EventNewRTCSession event) {
        logger.debug('newRTCSession => ' + event.toString());
        _session = event.session;
        if (_session.direction == 'incoming') {
          // Set event handlers.
          _session
              .addAllEventHandlers(_options()['eventHandlers'] as EventManager);
        }
        _notifyCallStateListeners(CallState(CallStateEnum.CALL_INITIATION));
      });

      this._ua.start();
    } catch (e, s) {
      logger.error(e.toString(), null, s);
    }
  }

  Map<String, Object> _options([bool voiceonly = false]) {
    // Register callbacks to desired call events
    EventManager eventHandlers = EventManager();

    eventHandlers.on(EventCallConnecting(), (EventCallConnecting event) {
      logger.debug('call connecting');
      _notifyCallStateListeners(CallState(CallStateEnum.CONNECTING));
    });

    eventHandlers.on(EventCallProgress(), (EventCallProgress event) {
      logger.debug('call is in progress');
      _notifyCallStateListeners(
          CallState(CallStateEnum.PROGRESS, originator: event.originator));
    });

    eventHandlers.on(EventCallFailed(), (EventCallFailed event) {
      logger.debug('call failed with cause: ' + (event.cause.toString()));
      _notifyCallStateListeners(CallState(CallStateEnum.FAILED,
          originator: event.originator, cause: event.cause));
      _session = null;
    });

    eventHandlers.on(EventCallEnded(), (EventCallEnded e) {
      logger.debug('call ended with cause: ' + (e.cause.toString()));
      _notifyCallStateListeners(CallState(CallStateEnum.ENDED,
          originator: e.originator, cause: e.cause));
      _session = null;
    });
    eventHandlers.on(EventCallAccepted(), (EventCallAccepted e) {
      logger.debug('call accepted');
      _notifyCallStateListeners(CallState(CallStateEnum.ACCEPTED));
    });
    eventHandlers.on(EventCallConfirmed(), (EventCallConfirmed e) {
      logger.debug('call confirmed');
      _notifyCallStateListeners(CallState(CallStateEnum.CONFIRMED));
    });
    eventHandlers.on(EventCallHold(), (EventCallHold e) {
      logger.debug('call hold');
      _notifyCallStateListeners(
          CallState(CallStateEnum.HOLD, originator: e.originator));
    });
    eventHandlers.on(EventCallUnhold(), (EventCallUnhold e) {
      logger.debug('call unhold');
      _notifyCallStateListeners(
          CallState(CallStateEnum.UNHOLD, originator: e.originator));
    });
    eventHandlers.on(EventCallMuted(), (EventCallMuted e) {
      logger.debug('call muted');
      _notifyCallStateListeners(
          CallState(CallStateEnum.MUTED, audio: e.audio, video: e.video));
    });
    eventHandlers.on(EventCallUnmuted(), (EventCallUnmuted e) {
      logger.debug('call unmuted');
      _notifyCallStateListeners(
          CallState(CallStateEnum.UNMUTED, audio: e.audio, video: e.video));
    });
    eventHandlers.on(EventStream(), (EventStream e) async {
      // Wating for callscreen ready.
      Timer(Duration(milliseconds: 100), () {
        _notifyCallStateListeners(CallState(CallStateEnum.STREAM,
            stream: e.stream, originator: e.originator));
      });
    });

    var _defaultOptions = {
      'eventHandlers': eventHandlers,
      'pcConfig': {
        'iceServers': [
          {'url': 'stun:stun.l.google.com:19302'},
          /*
           * turn server configuration example.
            {
              'url': 'turn:123.45.67.89:3478',
              'username': 'change_to_real_user',
              'credential': 'change_to_real_secret'
            },
          */
        ]
      },
      'mediaConstraints': {
        "audio": true,
        "video": voiceonly
            ? false
            : {
                "mandatory": {
                  "minWidth": '640',
                  "minHeight": '480',
                  "minFrameRate": '30',
                },
                "facingMode": "user",
                "optional": List<dynamic>(),
              }
      },
      'rtcOfferConstraints': {
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': !voiceonly,
        },
        'optional': List<dynamic>(),
      },
      'rtcAnswerConstraints': {
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': true,
        },
        'optional': List<dynamic>(),
      },
      'rtcConstraints': {
        'mandatory': Map<dynamic, dynamic>(),
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
        ],
      },
      'sessionTimersExpires': 120
    };
    return _defaultOptions;
  }

  void hold() {
    if (_session != null) {
      _session.hold();
    }
  }

  void unhold() {
    if (_session != null) {
      _session.unhold();
    }
  }

  void mute([bool audio = true, bool video = true]) {
    if (_session != null) {
      _session.mute(audio, video);
    }
  }

  void unmute([bool audio = true, bool video = true]) {
    if (_session != null) {
      _session.unmute(audio, video);
    }
  }

  void sendDTMF(String tones) {
    if (_session != null) {
      _session.sendDTMF(tones);
    }
  }

  Message sendMessage(String target, String body,
      [Map<String, dynamic> options]) {
    return this._ua.sendMessage(target, body, options);
  }

  void terminateSessions(Map<String, dynamic> options) {
    this._ua.terminateSessions(options);
  }

  Set<SipUaHelperListener> _sipUaHelperListeners = Set<SipUaHelperListener>();

  void addSipUaHelperListener(SipUaHelperListener listener) {
    _sipUaHelperListeners.add(listener);
  }

  void removeSipUaHelperListener(SipUaHelperListener listener) {
    _sipUaHelperListeners.remove(listener);
  }

  void _notifyTransportStateListeners(TransportState state) {
    _sipUaHelperListeners.forEach((listener) {
      listener.transportStateChanged(state);
    });
  }

  void _notifyRegsistrationStateListeners(RegistrationState state) {
    _sipUaHelperListeners.forEach((listener) {
      listener.registrationStateChanged(state);
    });
  }

  void _notifyCallStateListeners(CallState state) {
    _sipUaHelperListeners.forEach((listener) {
      listener.callStateChanged(state);
    });
  }
}

enum CallStateEnum {
  STREAM,
  UNMUTED,
  MUTED,
  CONNECTING,
  PROGRESS,
  FAILED,
  ENDED,
  ACCEPTED,
  CONFIRMED,
  HOLD,
  UNHOLD,
  NONE,
  CALL_INITIATION
}

class CallState {
  CallStateEnum state;
  ErrorCause cause;
  String originator;
  bool audio;
  bool video;
  MediaStream stream;
  CallState(this.state,
      {this.originator, this.audio, this.video, this.stream, this.cause});
}

enum RegistrationStateEnum {
  REGISTRATION_FAILED,
  REGISTERED,
  UNREGISTERED,
  NONE,
}

class RegistrationState {
  RegistrationStateEnum state;
  ErrorCause cause;
  RegistrationState({this.state, this.cause});
}

enum TransportStateEnum {
  CONNECTING,
  CONNECTED,
  DISCONNECTED,
  NONE,
}

class TransportState {
  TransportStateEnum state;
  Socket socket;
  ErrorCause cause;
  TransportState(this.state, {this.socket = null, this.cause});
}

abstract class SipUaHelperListener {
  void transportStateChanged(TransportState state);
  void registrationStateChanged(RegistrationState state);
  void callStateChanged(CallState state);
}
