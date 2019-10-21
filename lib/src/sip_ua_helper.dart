import 'dart:async';
import 'package:flutter_webrtc/media_stream.dart';

import 'Config.dart';
import 'Message.dart';
import 'RTCSession.dart';
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
  bool _registered = false;
  bool _connected = false;
  RegistrationStateEnum _registerState = RegistrationStateEnum.NONE;

  bool get registered => _registered;

  bool get connected => _connected;

  RegistrationStateEnum get registerState => _registerState;

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
    await this._ua.stop();
  }

  void register() {
    this._ua.register();
  }

  void unregister([bool all = true]) {
    this._ua.unregister(all: all);
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
      this._ua.on(EventConnecting(), (EventConnecting event) {
        logger.debug('connecting => ' + event.toString());
        _notifyRegsistrationStateListeners(RegistrationStateEnum.CONNECTING);
      });

      this._ua.on(EventConnected(), (EventConnected event) {
        logger.debug('connected => ' + event.toString());
        _notifyRegsistrationStateListeners(RegistrationStateEnum.CONNECTED);
        _connected = true;
      });

      this._ua.on(EventDisconnected(), (EventDisconnected event) {
        logger.debug('disconnected => ' + event.toString());
        _notifyRegsistrationStateListeners(RegistrationStateEnum.DISCONNECTED);
        _connected = false;
      });

      this._ua.on(EventRegistered(), (EventRegistered event) {
        logger.debug('registered => ' + event.toString());
        _registered = true;
        _registerState = RegistrationStateEnum.REGISTERED;
        _notifyRegsistrationStateListeners(RegistrationStateEnum.REGISTERED);
      });

      this._ua.on(EventUnregister(), (EventUnregister event) {
        logger.debug('unregistered => ' + event.toString());
        _registerState = RegistrationStateEnum.UNREGISTERED;
        _registered = false;
        _notifyRegsistrationStateListeners(RegistrationStateEnum.UNREGISTERED);
      });

      this._ua.on(EventRegistrationFailed(), (EventRegistrationFailed event) {
        logger.debug('registrationFailed => ' + (event.cause));
        _registerState = RegistrationStateEnum
            .REGISTRATION_FAILED; //'registrationFailed[${event.cause}]';
        _registered = false;
        _notifyRegsistrationStateListeners(
            RegistrationStateEnum.REGISTRATION_FAILED);
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

    eventHandlers.on(EventConnecting(), (EventConnecting event) {
      logger.debug('call connecting');
      _notifyCallStateListeners(CallState(CallStateEnum.CONNECTING));
    });

    eventHandlers.on(EventProgress(), (EventProgress event) {
      logger.debug('call is in progress');
      _notifyCallStateListeners(
          CallState(CallStateEnum.PROGRESS, originator: event.originator));
    });

    eventHandlers.on(EventFailed(), (EventFailed event) {
      logger.debug('call failed with cause: ' + (event.cause));
      _notifyCallStateListeners(
          CallState(CallStateEnum.FAILED, originator: event.originator));
      _session = null;
    });

    eventHandlers.on(EventEnded(), (EventEnded e) {
      logger.debug('call ended with cause: ' + (e.cause));
      _notifyCallStateListeners(
          CallState(CallStateEnum.ENDED, originator: e.originator));
      _session = null;
    });
    eventHandlers.on(EventCallAccepted(), (EventCallAccepted e) {
      logger.debug('call accepted');
      _notifyCallStateListeners(CallState(CallStateEnum.ACCEPTED));
    });
    eventHandlers.on(EventConfirmed(), (EventConfirmed e) {
      logger.debug('call confirmed');
      _notifyCallStateListeners(CallState(CallStateEnum.CONFIRMED));
    });
    eventHandlers.on(EventHold(), (EventHold e) {
      logger.debug('call hold');
      _notifyCallStateListeners(
          CallState(CallStateEnum.HOLD, originator: e.originator));
    });
    eventHandlers.on(EventUnhold(), (EventUnhold e) {
      logger.debug('call unhold');
      _notifyCallStateListeners(
          CallState(CallStateEnum.UNHOLD, originator: e.originator));
    });
    eventHandlers.on(EventMuted(), (EventMuted e) {
      logger.debug('call muted');
      _notifyCallStateListeners(
          CallState(CallStateEnum.MUTED, audio: e.audio, video: e.video));
    });
    eventHandlers.on(EventUnmuted(), (EventUnmuted e) {
      logger.debug('call unmuted');
      _notifyCallStateListeners(
          CallState(CallStateEnum.UNMUTED, audio: e.audio, video: e.video));
    });
    eventHandlers.on(EventStream(), (EventStream e) async {
      // Wating for callscreen ready.
      Timer(Duration(milliseconds: 100), () {
        _notifyCallStateListeners(
            CallState(CallStateEnum.STREAM, stream: e.stream));
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

  void _notifyRegsistrationStateListeners(RegistrationStateEnum state) {
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

abstract class SipUaHelperListener {
  void registrationStateChanged(RegistrationStateEnum state);
  void callStateChanged(CallState state);
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
  String originator;
  bool audio;
  bool video;
  MediaStream stream;

  CallState(this.state, {this.originator, this.audio, this.video, this.stream});
}

enum RegistrationStateEnum {
  CONNECTING,
  CONNECTED,
  DISCONNECTED,
  REGISTRATION_FAILED,
  REGISTERED,
  UNREGISTERED,
  NONE,
}
