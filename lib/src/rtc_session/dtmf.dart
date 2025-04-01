import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../sip_ua.dart';
import '../constants.dart';
import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../exceptions.dart' as Exceptions;
import '../logger.dart';
import '../rtc_session.dart';
import '../utils.dart' as Utils;

class C {
  static const int MIN_DURATION = 70;
  static const int MAX_DURATION = 6000;
  static const int DEFAULT_DURATION = 100;
  static const int MIN_INTER_TONE_GAP = 50;
  static const int DEFAULT_INTER_TONE_GAP = 500;
}

class DTMF extends EventManager {
  DTMF(this._session, {DtmfMode mode = DtmfMode.INFO}) {
    _mode = mode;
  }

  final RTCSession _session;
  DtmfMode? _mode;
  Direction? _direction;
  String? _tone;
  int? _duration;
  int? _interToneGap;
  IncomingRequest? _request;
  late EventManager _eventHandlers;

  String? get tone => _tone;

  int? get duration => _duration;

  Direction? get direction => _direction;

  void send(String tone, Map<String, dynamic> options) {
    if (tone == null) {
      throw Exceptions.TypeError('Not enough arguments');
    }

    _direction = Direction.outgoing;

    // Check RTCSession Status.
    if (_session.state != RtcSessionState.confirmed &&
        _session.state != RtcSessionState.waitingForAck) {
      throw Exceptions.InvalidStateError(_session.status);
    }

    List<dynamic> extraHeaders = options['extraHeaders'] != null
        ? Utils.cloneArray(options['extraHeaders'])
        : <dynamic>[];

    _eventHandlers = options['eventHandlers'] ?? EventManager();

    // Check tone value.
    if (!tone.contains(RegExp(r'^[0-9A-DR#*]$'))) {
      throw Exceptions.TypeError('Invalid tone: $tone');
    } else {
      _tone = tone;
    }

    // Duration is checked/corrected in RTCSession.
    _duration = options['duration'];
    _interToneGap = options['interToneGap'];

    if (_mode == DtmfMode.RFC2833) {
      RTCDTMFSender? dtmfSender = _session.dtmfSender;
      dtmfSender?.insertDTMF(_tone!,
          duration: _duration!, interToneGap: _interToneGap!);
    } else if (_mode == DtmfMode.INFO) {
      extraHeaders.add('Content-Type: application/dtmf-relay');

      String body = 'Signal=$_tone\r\n';

      body += 'Duration=$_duration';

      _session.newDTMF(Originator.local, this, _request);

      EventManager handlers = EventManager();
      handlers.on(EventOnSuccessResponse(), (EventOnSuccessResponse event) {
        emit(EventSucceeded(
            originator: Originator.remote, response: event.response));
      });
      handlers.on(EventOnErrorResponse(), (EventOnErrorResponse event) {
        _eventHandlers.emit(EventOnFialed());
        emit(EventOnFialed());
        emit(EventCallFailed(
            originator: Originator.remote, response: event.response));
      });
      handlers.on(EventOnRequestTimeout(), (EventOnRequestTimeout event) {
        _session.onRequestTimeout();
      });
      handlers.on(EventOnTransportError(), (EventOnTransportError event) {
        _session.onTransportError();
      });

      handlers.on(EventOnDialogError(), (EventOnDialogError event) {
        _session.onDialogError();
      });

      _session.sendRequest(SipMethod.INFO, <String, dynamic>{
        'extraHeaders': extraHeaders,
        'eventHandlers': handlers,
        'body': body
      });
    }
  }

  void init_incoming(IncomingRequest request) {
    String reg_tone = r'^(Signal\s*?=\s*?)([0-9A-D#*]{1})(\s)?.*';
    String reg_duration = r'^(Duration\s?=\s?)([0-9]{1,4})(\s)?.*';

    _direction = Direction.incoming;
    _request = request;

    request.reply(200);

    if (request.body != null) {
      List<String> body = request.body!.split('\n');

      if (body.isNotEmpty) {
        if (body[0].contains(RegExp(reg_tone))) {
          _tone = body[0].replaceAll(reg_tone, '\$2');
        }
      }
      if (body.length >= 2) {
        if (body[1].contains(RegExp(reg_duration))) {
          _duration =
              int.tryParse(body[1].replaceAll(reg_duration, '\$2'), radix: 10);
        }
      }
    }

    _duration ??= C.DEFAULT_DURATION;

    if (_tone == null) {
      logger.d('invalid INFO DTMF received, discarded');
    } else {
      _session.newDTMF(Originator.remote, this, request);
    }
  }
}
