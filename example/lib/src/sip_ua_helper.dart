import 'dart:async';
import 'package:sip_ua/sip_ua.dart';
import 'package:events2/events2.dart';
import 'package:sip_ua/src/RTCSession.dart';

class SIPUAHelper extends EventEmitter {
  UA _ua;
  Settings _settings;
  final logger = new Logger('SIPUA::Helper');
  RTCSession _session;
  bool _registered = false;
  bool _connected = false;
  var _registerState = 'new';
  var _localStream;
  var _remoteStream;

  SIPUAHelper();

  debug(msg) => logger.debug(msg);

  debugerror(error) => logger.error(error);

  RTCSession get session => _session;

  bool get registered => _registered;

  bool get connected => _connected;

  get registerState => _registerState;

  get localStream => _localStream;

  get remoteStream => _remoteStream;

  _handleSocketState(state, data) {
    this.emit('socketState', state, data);
  }

  _handleRegisterState(state, data) {
    this.emit('registerState', state, data);
  }

  _handleUAState(state, data) {
    this.emit('uaState', state, data);
  }

  _handleCallState(state, data) {
    this.emit('callState', state, data);
  }

  start(wsUrl, uri, [password, displayName, wsExtraHeaders]) async {
    if (this._ua != null) {
      debugerror('UA instance already exist!');
      this._ua.start();
      return;
    }
    _settings = new Settings();
    var socket = new WebSocketInterface(wsUrl, wsExtraHeaders);
    _settings.sockets = [socket];
    _settings.uri = uri;
    _settings.password = password;
    _settings.display_name = displayName;

    try {
      this._ua = new UA(_settings);
      this._ua.on('onnecting', (data) {
        debug('onnecting => ' + data.toString());
        _handleSocketState('onnecting', data);
      });

      this._ua.on('connected', (data) {
        debug('connected => ' + data.toString());
        _handleSocketState('connected', data);
        _connected = true;
      });

      this._ua.on('disconnected', (data) {
        debug('disconnected => ' + data.toString());
        _handleSocketState('disconnected', data);
        _connected = false;
      });

      this._ua.on('registered', (data) {
        debug('registered => ' + data.toString());
        _registered = true;
        _registerState = 'registered';
        _handleRegisterState('registered', data);
      });

      this._ua.on('unregistered', (data) {
        debug('unregistered => ' + data.toString());
        _registerState = 'unregistered';
        _registered = false;
        _handleRegisterState('unregistered', data);
      });

      this._ua.on('registrationFailed', (data) {
        debug('registrationFailed => ' + data['cause']);
        _registerState = 'registrationFailed[${data['cause']}]';
        _registered = false;
        _handleRegisterState('registrationFailed', data);
      });

      this._ua.on('newRTCSession', (data) {
        debug('newRTCSession => ' + data.toString());
        _session = data['session'];
        if (_session.direction == 'incoming') {
          // Set event handlers.
          options()['eventHandlers'].forEach((event, func) {
            _session.on(event, func);
          });
        }
        _handleUAState('newRTCSession', data);
      });

      this._ua.on('newMessage', (data) {
        debug('newMessage => ' + data.toString());
        _handleUAState('newMessage', data);
      });

      this._ua.on('sipEvent', (data) {
        debug('sipEvent => ' + data.toString());
        _handleUAState('sipEvent', data);
      });
      this._ua.start();
    } catch (e) {
      debugerror(e.toString());
    }
  }

  stop() async {
    await this._ua.stop();
  }

  register() {
    this._ua.register();
  }

  unregister([all = true]) {
    this._ua.unregister(all: all);
  }

  options([voiceonly]) {
    voiceonly = voiceonly ?? false;
    // Register callbacks to desired call events
    var eventHandlers = {
      'connecting': (e) {
        debug('call connecting');
        _handleCallState('connecting', e);
      },
      'progress': (e) {
        debug('call is in progress');
        _handleCallState('progress', e);
      },
      'failed': (e) {
        debug('call failed with cause: ' + e['cause']);
        _handleCallState('failed', e);
        _session = null;
        var cause = 'failed (${e['cause']})';
        _localStream = null;
        _remoteStream = null;
      },
      'ended': (e) {
        debug('call ended with cause: ' + e['cause']);
        _handleCallState('ended', e);
        _session = null;
        _localStream = null;
        _remoteStream = null;
      },
      'accepted': (e) {
        debug('call accepted');
        _handleCallState('accepted', e);
      },
      'confirmed': (e) {
        debug('call confirmed');
        _handleCallState('confirmed', e);
      },
      'hold': (e) {
        debug('call hold');
        _handleCallState('hold', e);
      },
      'unhold': (e) {
        debug('call unhold');
        _handleCallState('unhold', e);
      },
      'muted': (e) {
        debug('call muted');
        _handleCallState('muted', e);
      },
      'unmuted': (e) {
        debug('call unmuted');
        _handleCallState('unmuted', e);
      },
      'stream': (e) async {
        // Wating for callscreen ready.
        new Timer(Duration(milliseconds: 100), () {
          _handleCallState('stream', e);
        });
      }
    };

    var defaultOptions = {
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
                "optional": [],
              }
      },
      'rtcOfferConstraints': {
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': true,
        },
        'optional': [],
      },
      'rtcAnswerConstraints': {
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': true,
        },
        'optional': [],
      },
      'rtcConstraints': {
        'mandatory': {},
        'optional': [
          {'DtlsSrtpKeyAgreement': true},
        ],
      }
    };
    return defaultOptions;
  }

  connect(uri, [voiceonly]) async {
    if (_ua != null) {
      _session = _ua.call(uri, this.options(voiceonly));
      return _session;
    }
    return null;
  }

  answer() {
    if (_session != null) {
      _session.answer(this.options());
    }
  }

  hangup() {
    if (_session != null) {
      _session.terminate();
    }
  }

  sendMessage(target, body, [options]) {
    return this._ua.sendMessage(target, body, options);
  }

  terminateSessions(options) {
    return this._ua.terminateSessions(options);
  }
}
