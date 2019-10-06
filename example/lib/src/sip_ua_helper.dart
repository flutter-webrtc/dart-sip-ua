import 'dart:async';
import 'package:sip_ua/sip_ua.dart';
import 'package:events2/events2.dart';
import 'package:sip_ua/src/RTCSession.dart';
import 'package:sip_ua/src/Message.dart';

class SIPUAHelper extends EventEmitter {
  UA _ua;
  Settings _settings;
  final logger = Logger('SIPUA::Helper');
  RTCSession _session;
  bool _registered = false;
  bool _connected = false;
  var _registerState = 'new';

  void debug(dynamic msg) => logger.debug(msg);

  void debugerror(dynamic error) => logger.error(error);

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
      debugerror(
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
      this._ua.on('onnecting', (Map<String, dynamic> data) {
        debug('onnecting => ' + data.toString());
        _handleSocketState('onnecting', data);
      });

      this._ua.on('connected', (Map<String, dynamic> data) {
        debug('connected => ' + data.toString());
        _handleSocketState('connected', data);
        _connected = true;
      });

      this._ua.on('disconnected', (Map<String, dynamic> data) {
        debug('disconnected => ' + data.toString());
        _handleSocketState('disconnected', data);
        _connected = false;
      });

      this._ua.on('registered', (Map<String, dynamic> data) {
        debug('registered => ' + data.toString());
        _registered = true;
        _registerState = 'registered';
        _handleRegisterState('registered', data);
      });

      this._ua.on('unregistered', (Map<String, dynamic> data) {
        debug('unregistered => ' + data.toString());
        _registerState = 'unregistered';
        _registered = false;
        _handleRegisterState('unregistered', data);
      });

      this._ua.on('registrationFailed', (Map<String, dynamic> data) {
        debug('registrationFailed => ' + (data['cause'] as String));
        _registerState = 'registrationFailed[${data['cause']}]';
        _registered = false;
        _handleRegisterState('registrationFailed', data);
      });

      this._ua.on('newRTCSession', (Map<String, dynamic> data) {
        debug('newRTCSession => ' + data.toString());
        _session = data['session'] as RTCSession;
        if (_session.direction == 'incoming') {
          // Set event handlers.
          (_options()['eventHandlers'] as Map<String, Function>)
              .forEach((String event, Function func) {
            _session.on(event, func);
          });
        }
        _handleUAState('newRTCSession', data);
      });

      this._ua.on('newMessage', (Map<String, dynamic> data) {
        debug('newMessage => ' + data.toString());
        _handleUAState('newMessage', data);
      });

      this._ua.on('sipEvent', (Map<String, dynamic> data) {
        debug('sipEvent => ' + data.toString());
        _handleUAState('sipEvent', data);
      });
      this._ua.start();
    } catch (e) {
      debugerror(e.toString());
    }
  }

  Map<String, Object> _options([bool voiceonly = false]) {
    // Register callbacks to desired call events
    var eventHandlers = {
      'connecting': (Map<String, dynamic> e) {
        debug('call connecting');
        _handleCallState('connecting', e);
      },
      'progress': (Map<String, dynamic> e) {
        debug('call is in progress');
        _handleCallState('progress', e);
      },
      'failed': (Map<String, dynamic> e) {
        debug('call failed with cause: ' + (e['cause'] as String));
        _handleCallState('failed', e);
        _session = null;
        var cause = 'failed (${e['cause']})';
      },
      'ended': (Map<String, dynamic> e) {
        debug('call ended with cause: ' + (e['cause'] as String));
        _handleCallState('ended', e);
        _session = null;
      },
      'accepted': (Map<String, dynamic> e) {
        debug('call accepted');
        _handleCallState('accepted', e);
      },
      'confirmed': (Map<String, dynamic> e) {
        debug('call confirmed');
        _handleCallState('confirmed', e);
      },
      'hold': (Map<String, dynamic> e) {
        debug('call hold');
        _handleCallState('hold', e);
      },
      'unhold': (Map<String, dynamic> e) {
        debug('call unhold');
        _handleCallState('unhold', e);
      },
      'muted': (Map<String, dynamic> e) {
        debug('call muted');
        _handleCallState('muted', e);
      },
      'unmuted': (Map<String, dynamic> e) {
        debug('call unmuted');
        _handleCallState('unmuted', e);
      },
      'stream': (Map<String, dynamic> e) async {
        // Wating for callscreen ready.
        Timer(Duration(milliseconds: 100), () {
          _handleCallState('stream', e);
        });
      }
    };

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

  void _handleSocketState(String state, Map<String, dynamic> data) {
    this.emit('socketState', state, data);
  }

  void _handleRegisterState(String state, Map<String, dynamic> data) {
    this.emit('registerState', state, data);
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

  void _handleCallState(String state, Map<String, dynamic> data) {
    this.emit('callState', state, data);
  }

  void _handleUAState(String state, Map<String, dynamic> data) {
    this.emit('uaState', state, data);
  }

  Message sendMessage(String target, String body,
      [Map<String, dynamic> options]) {
    return this._ua.sendMessage(target, body, options);
  }

  void terminateSessions(Map<String, dynamic> options) {
    this._ua.terminateSessions(options);
  }
}
