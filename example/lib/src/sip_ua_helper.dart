import 'dart:async';
import 'package:flutter_webrtc/media_stream.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:sip_ua/src/Message.dart';
import 'package:sip_ua/src/RTCSession.dart';
import 'package:sip_ua/src/SIPMessage.dart';
import 'package:sip_ua/src/logger.dart';
import 'package:sip_ua/src/event_manager/event_manager.dart';

class SIPUAHelper extends EventManager {
  UA _ua;
  Settings _settings;
  final Log logger = Log();
  RTCSession _session;
  bool _registered = false;
  bool _connected = false;
  var _registerState = 'new';

  RTCSession get session => _session;

  bool get registered => _registered;

  bool get connected => _connected;

  String get registerState => _registerState;

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
      logger.error("Not connected, you will need to register.");
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
      logger.error(
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
        _handleSocketState('connecting', null);
      });

      this._ua.on(EventConnected(), (EventConnected event) {
        logger.debug('connected => ' + event.toString());
        _handleSocketState('connected', null);
        _connected = true;
      });

      this._ua.on(EventDisconnected(), (EventDisconnected event) {
        logger.debug('disconnected => ' + event.toString());
        _handleSocketState('disconnected', null);
        _connected = false;
      });

      this._ua.on(EventRegistered(), (EventRegistered event) {
        logger.debug('registered => ' + event.toString());
        _registered = true;
        _registerState = 'registered';
        _handleRegisterState('registered', event.response);
      });

      this._ua.on(EventUnregister(), (EventUnregister event) {
        logger.debug('unregistered => ' + event.toString());
        _registerState = 'unregistered';
        _registered = false;
        _handleRegisterState('unregistered', event.response);
      });

      this._ua.on(EventRegistrationFailed(), (EventRegistrationFailed event) {
        logger.debug('registrationFailed => ' + (event.cause));
        _registerState = 'registrationFailed[${event.cause}]';
        _registered = false;
        _handleRegisterState('registrationFailed', event.response);
      });

      this._ua.on(EventNewRTCSession(), (EventNewRTCSession event) {
        logger.debug('newRTCSession => ' + event.toString());
        _session = event.session;
        if (_session.direction == 'incoming') {
          // Set event handlers.
          _session
              .addAllEventHandlers(_options()['eventHandlers'] as EventManager);
        }
        _handleUAState(EventUaState(state: "newRTCSession"));
      });

      this._ua.on(EventNewMessage(), (EventNewMessage event) {
        logger.debug('newMessage => ' + event.toString());
        _handleUAState(EventUaState(state: "newMessage"));
      });

      this._ua.on(EventSipEvent(), (EventSipEvent event) {
        logger.debug('sipEvent => ' + event.toString());
        _handleUAState(EventUaState(state: "sipEvent"));
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
      _handleCallState('connecting', null, null, null, null, null);
    });

    eventHandlers.on(EventProgress(), (EventProgress event) {
      logger.debug('call is in progress');
      _handleCallState(
          'progress', event.response, null, event.originator, null, null);
    });

    eventHandlers.on(EventFailed(), (EventFailed event) {
      logger.debug('call failed with cause: ' + (event.cause));
      _handleCallState(
          'failed', event.response, null, event.originator, null, null);
      _session = null;
    });

    eventHandlers.on(EventEnded(), (EventEnded e) {
      logger.debug('call ended with cause: ' + (e.cause));
      _handleCallState('ended', null, null, e.originator, null, null);
      _session = null;
    });
    eventHandlers.on(EventCallAccepted(), (EventCallAccepted e) {
      logger.debug('call accepted');
      _handleCallState('accepted', null, null, null, null, null);
    });
    eventHandlers.on(EventConfirmed(), (EventConfirmed e) {
      logger.debug('call confirmed');
      _handleCallState('confirmed', null, null, null, null, null);
    });
    eventHandlers.on(EventHold(), (EventHold e) {
      logger.debug('call hold');
      _handleCallState('hold', null, null, e.originator, null, null);
    });
    eventHandlers.on(EventUnhold(), (EventUnhold e) {
      logger.debug('call unhold');
      _handleCallState('unhold', null, null, null, null, null);
    });
    eventHandlers.on(EventMuted(), (EventMuted e) {
      logger.debug('call muted');
      _handleCallState('muted', null, null, null, e.audio, e.video);
    });
    eventHandlers.on(EventUnmuted(), (EventUnmuted e) {
      logger.debug('call unmuted');
      _handleCallState('unmuted', null, null, null, e.audio, e.video);
    });
    eventHandlers.on(EventStream(), (EventStream e) async {
      // Wating for callscreen ready.
      Timer(Duration(milliseconds: 100), () {
        _handleCallState('stream', null, e.stream, null, null, null);
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

  void _handleSocketState(String state, IncomingMessage response) {
    this.emit(EventSocketState(state: state, response: response));
  }

  void _handleRegisterState(String state, IncomingMessage response) {
    this.emit(EventRegisterState(state: state, response: response));
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

  void _handleCallState(String state, dynamic response, MediaStream stream,
      String originator, bool audio, bool video) {
    this.emit(EventCallState(
        state: state,
        response: response,
        stream: stream,
        originator: originator,
        audio: audio,
        video: video));
  }

  void _handleUAState(EventUaState event) {
    logger.error("event $event");
    this.emit(event);
  }

  Message sendMessage(String target, String body,
      [Map<String, dynamic> options]) {
    return this._ua.sendMessage(target, body, options);
  }

  void terminateSessions(Map<String, dynamic> options) {
    this._ua.terminateSessions(options);
  }
}
