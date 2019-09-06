import 'package:sip_ua/sip_ua.dart';
import 'package:sip_ua/src/logger.dart';
import 'package:events2/events2.dart';

class SIPUAHelper extends EventEmitter {
  UA _ua;
  Settings _settings;
  String _url;
  final logger = new Logger('SIPUA::Helper');
  var _wsExtraHeaders;

  SIPUAHelper(this._url, [this._wsExtraHeaders]);

  debug(msg) => logger.debug(msg);

  debugerror(error) => logger.error(error);

  start(uri, [password, displayName]) async {
    _settings = new Settings();
    var socket = new WebSocketInterface(this._url, this._wsExtraHeaders);
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
      });

      this._ua.on('disconnected', (data) {
        debug('disconnected => ' + data.toString());
        this.emit('disconnected', data);
      });

      this._ua.on('registered', (data) {
        debug('registered => ' + data.toString());
        this.emit('registered', data);
      });

      this._ua.on('unregistered', (data) {
        debug('unregistered => ' + data.toString());
        this.emit('unregistered', data);
      });

      this._ua.on('registrationFailed', (data) {
        debug('registrationFailed => ' + data['cause']);
        this.emit('registrationFailed', data);
      });

      this._ua.on('newRTCSession', (data) {
        //debug('newRTCSession => ' + data.toString());
        this.emit('newRTCSession', data);
      });

      this._ua.on('newMessage', (data) {
        debug('newMessage => ' + data.toString());
        this.emit('newMessage', data);
      });

      this._ua.on('sipEvent', (data) {
        debug('sipEvent => ' + data.toString());
        this.emit('sipEvent', data);
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

  connect(uri, [options]) async {
    // Register callbacks to desired call events
    var eventHandlers = {
      'progress': (e) {
        debug('call is in progress');
        this.emit('progress', e);
      },
      'failed': (e) {
        debug('call failed with cause: ' + e['cause']);
        this.emit('failed', e);
      },
      'ended': (e) {
        debug('call ended with cause: ' + e['cause']);
        this.emit('ended', e);
      },
      'confirmed': (e) {
        debug('call confirmed');
        this.emit('confirmed', e);
      }
    };

    var options = {
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

    var session = this._ua.call(uri, options);
    return session;
  }

  sendMessage(target, body, [options]) {
    return this._ua.sendMessage(target, body, options);
  }

  terminateSessions(options) {
    return this._ua.terminateSessions(options);
  }

  isRegistered() {
    return this._ua.isRegistered();
  }

  isConnected() {
    return this._ua.isConnected();
  }
}
