import 'package:sip_ua/sip_ua.dart';
import 'package:events2/events2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/webrtc.dart';

class SIPUAHelper extends EventEmitter with ChangeNotifier {
  UA _ua;
  Settings _settings;
  final logger = new Logger('SIPUA::Helper');
  var _session;
  var _registered = false;
  var _direction;
  var _connected = false;
  var _sessionState = 'new';
  var _registerState = 'new';
  var _localStream;
  var _remoteStream;

  SIPUAHelper();

  debug(msg) => logger.debug(msg);

  debugerror(error) => logger.error(error);

  get session => _session;

  get registered => _registered;

  get direction => _direction;

  get connected => _connected;

  get registerState => _registerState;

  get sessionState => _sessionState;

  get localStream => _localStream;

  get remoteStream => _remoteStream;

  notify() => notifyListeners();

  start(wsUrl, uri, [password, displayName, wsExtraHeaders]) async {
    if (this._ua != null) {
      debugerror('UA instance already exist!');
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
        this.emit('onnecting', data);
      });

      this._ua.on('connected', (data) {
        debug('connected => ' + data.toString());
        this.emit('connected', data);
        _connected = true;
        notify();
      });

      this._ua.on('disconnected', (data) {
        debug('disconnected => ' + data.toString());
        this.emit('disconnected', data);
        _connected = false;
        notify();
      });

      this._ua.on('registered', (data) {
        debug('registered => ' + data.toString());
        _registered = true;
        _registerState = 'registered';
        notify();
      });

      this._ua.on('unregistered', (data) {
        debug('unregistered => ' + data.toString());
        _registerState = 'unregistered';
        _registered = false;
        notify();
      });

      this._ua.on('registrationFailed', (data) {
        debug('registrationFailed => ' + data['cause']);
        _registerState = 'registrationFailed[${data['cause']}]';
        _registered = false;
        notify();
      });

      this._ua.on('newRTCSession', (data) {
        debug('newRTCSession => ' + data.toString());
        _session = data['session'];
        _direction = _session.direction;
        if (_session.direction == 'incoming') {
          // Set event handlers.
          options()['eventHandlers'].forEach((event, func) {
            _session.on(event, func);
          });
        }
        notify();
        this.emit('newRTCSession', data);
      });

      this._ua.on('newMessage', (data) {
        debug('newMessage => ' + data.toString());
        this.emit('newMessage', data);
        notify();
      });

      this._ua.on('sipEvent', (data) {
        debug('sipEvent => ' + data.toString());
        this.emit('sipEvent', data);
        notify();
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

  options() {
    // Register callbacks to desired call events
    var eventHandlers = {
      'progress': (e) {
        debug('call is in progress');
        this.emit('progress', e);
        _sessionState = 'progress';
        notify();
      },
      'failed': (e) {
        debug('call failed with cause: ' + e['cause']);
        this.emit('failed', e);
        _session = null;
        _sessionState = 'failed';
        _localStream = null;
        _remoteStream = null;
        notify();
      },
      'ended': (e) {
        debug('call ended with cause: ' + e['cause']);
        this.emit('ended', e);
        _session = null;
        _sessionState = 'ended';
        _localStream = null;
        _remoteStream = null;
        notify();
      },
      'confirmed': (e) {
        debug('call confirmed');
        this.emit('confirmed', e);
        _sessionState = 'confirmed';
        notify();
      },
      'stream': (e) async {
        this.emit('stream', e);
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
        "video": {
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

  connect(uri) async {
    _session = this._ua.call(uri, this.options());
    return _session;
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
