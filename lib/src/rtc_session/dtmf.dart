import '../../sip_ua.dart';
import '../constants.dart';
import '../exceptions.dart' as Exceptions;
import '../rtc_session.dart' as RTCSession;
import '../utils.dart' as Utils;
import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../logger.dart';

class C {
  static const MIN_DURATION = 70;
  static const MAX_DURATION = 6000;
  static const DEFAULT_DURATION = 100;
  static const MIN_INTER_TONE_GAP = 50;
  static const DEFAULT_INTER_TONE_GAP = 500;
}

class DTMF extends EventManager {
  var _session;
  var _direction;
  var _tone;
  var _duration;
  var _request;
  EventManager eventHandlers;
  final logger = Log();

  DTMF(session) {
    this._session = session;
    this._direction = null;
    this._tone = null;
    this._duration = null;
    this._request = null;
  }

  get tone => this._tone;

  get duration => this._duration;

  get direction => this._direction;

  send(tone, options) {
    if (tone == null) {
      throw new Exceptions.TypeError('Not enough arguments');
    }

    this._direction = 'outgoing';

    // Check RTCSession Status.
    if (this._session.status != RTCSession.C.STATUS_CONFIRMED &&
        this._session.status != RTCSession.C.STATUS_WAITING_FOR_ACK) {
      throw new Exceptions.InvalidStateError(this._session.status);
    }

    var extraHeaders = Utils.cloneArray(options['extraHeaders']);

    this.eventHandlers = options['eventHandlers'] ?? EventManager();

    // Check tone type.
    if (tone is String) {
      tone = tone.toUpperCase();
    } else if (tone is num) {
      tone = tone.toString();
    } else {
      throw new Exceptions.TypeError('Invalid tone: ${tone}');
    }

    // Check tone value.
    if (!tone.contains(new RegExp(r'^[0-9A-DR#*]$'))) {
      throw new Exceptions.TypeError('Invalid tone: ${tone}');
    } else {
      this._tone = tone;
    }

    // Duration is checked/corrected in RTCSession.
    this._duration = options['duration'];

    extraHeaders.add('Content-Type: application/dtmf-relay');

    var body = 'Signal=${this._tone}\r\n';

    body += 'Duration=${this._duration}';

    this._session.newDTMF('local', this, this._request);

    EventManager handlers = EventManager();
    handlers.on(EventOnSuccessResponse(), (EventOnSuccessResponse event) {
      this.emit(EventSucceeded(originator: 'remote', response: event.response));
    });
    handlers.on(EventOnErrorResponse(), (EventOnErrorResponse event) {
      this.eventHandlers.emit(EventOnFialed());
      this.emit(EventOnFialed());
      this.emit(
          EventCallFailed(originator: 'remote', response: event.response));
    });
    handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout event) {
      this._session.onRequestTimeout();
    });
    handlers.on(EventOnTransportError(), (EventOnTransportError event) {
      this._session.onTransportError();
    });

    handlers.on(EventOnDialogError(), (EventOnDialogError event) {
      this._session.onDialogError();
    });

    this._session.sendRequest(SipMethod.INFO, {
      'extraHeaders': extraHeaders,
      'eventHandlers': handlers,
      'body': body
    });
  }

  init_incoming(request) {
    var reg_tone = r'^(Signal\s*?=\s*?)([0-9A-D#*]{1})(\s)?.*';
    var reg_duration = r'^(Duration\s?=\s?)([0-9]{1,4})(\s)?.*';

    this._direction = 'incoming';
    this._request = request;

    request.reply(200);

    if (request.body != null) {
      var body = request.body.split('\n');

      if (body.length >= 1) {
        if ((body[0]).contains(new RegExp(reg_tone))) {
          this._tone = body[0].replaceAll(reg_tone, '\$2');
        }
      }
      if (body.length >= 2) {
        if ((body[1]).contains(new RegExp(reg_duration))) {
          this._duration =
              Utils.parseInt(body[1].replaceAll(reg_duration, '\$2'), 10);
        }
      }
    }

    if (this._duration == null) {
      this._duration = C.DEFAULT_DURATION;
    }

    if (this._tone == null) {
      logger.debug('invalid INFO DTMF received, discarded');
    } else {
      this._session.newDTMF('remote', this, request);
    }
  }
}
