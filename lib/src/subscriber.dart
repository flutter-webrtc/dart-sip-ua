import 'dart:async';

import 'package:collection/collection.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:sip_ua/src/constants.dart';
import 'package:sip_ua/src/dialog.dart';
import 'package:sip_ua/src/event_manager/internal_events.dart';
import 'package:sip_ua/src/event_manager/subscriber_events.dart';
import 'package:sip_ua/src/exceptions.dart';
import 'package:sip_ua/src/grammar.dart';
import 'package:sip_ua/src/logger.dart';
import 'package:sip_ua/src/request_sender.dart';
import 'package:sip_ua/src/rtc_session.dart';
import 'package:sip_ua/src/sanity_check.dart';
import 'package:sip_ua/src/sip_message.dart';
import 'package:sip_ua/src/timers.dart';
import 'package:sip_ua/src/ua.dart';
import 'package:sip_ua/src/utils.dart';

import 'event_manager/event_manager.dart';

/**
 * Termination codes.
 */
class C {
  // Termination codes.
  static const int SUBSCRIBE_RESPONSE_TIMEOUT = 0;
  static const int SUBSCRIBE_TRANSPORT_ERROR = 1;
  static const int SUBSCRIBE_NON_OK_RESPONSE = 2;
  static const int SUBSCRIBE_BAD_OK_RESPONSE = 3;
  static const int SUBSCRIBE_FAILED_AUTHENTICATION = 4;
  static const int UNSUBSCRIBE_TIMEOUT = 5;
  static const int RECEIVE_FINAL_NOTIFY = 6;
  static const int RECEIVE_BAD_NOTIFY = 7;

  // Subscriber states.
  static const int STATE_PENDING = 0;
  static const int STATE_ACTIVE = 1;
  static const int STATE_TERMINATED = 2;
  static const int STATE_INIT = 3;
  static const int STATE_NOTIFY_WAIT = 4;
}

class Subscriber extends EventManager {
  Subscriber(this._ua, this._target, String eventName, String accept,
      [int expires = 900,
      String? contentType,
      String? allowEvents,
      Map<String, dynamic> requestParams = const <String, dynamic>{},
      List<String> extraHeaders = const <String>[]]) {
    logger.debug('new');

    _expires = expires;

    // Used to subscribe with body.
    _contentType = contentType;

    _params = requestParams;

    _params['from_tag'] = newTag();

    _params['to_tag'] = null;

    _params['call_id'] = createRandomToken(20);

    if (_params['cseq'] == null) {
      _params['cseq'] = Math.floor((Math.random() * 10000) + 1);
    }

    _state = C.STATE_INIT;

    _dialog = null;

    _expires_timer = null;

    _expires_timestamp = null;

    _terminated = false;

    _unsubscribe_timeout_timer = null;

    dynamic parsed = Grammar.parse(eventName, 'Event');

    if (parsed == -1) {
      throw TypeError('eventName - wrong format');
    }

    _event_name = parsed.event;
    // this._event_id = parsed.params && parsed.params.id;
    _event_id = parsed.params && parsed.params.id;

    String eventValue = _event_name;

    if (_event_id != null) {
      eventValue += ';id=$_event_id';
    }

    _headers = cloneArray(extraHeaders);

    _headers.addAll(<String>[
      'Event: $eventValue',
      'Expires: $_expires',
      'Accept: $accept'
    ]);

    if (!_headers.any((dynamic element) => element.startsWith('Contact'))) {
      String contact = 'Contact: ${_ua.contact.toString()}';

      _headers.add(contact);
    }

    if (allowEvents != null) {
      _headers.add('Allow-Events: $allowEvents');
    }

    // To enqueue subscribes created before receive initial subscribe OK.
    _queue = <Map<String, dynamic>>[];
  }

  final UA _ua;

  final String _target;

  late int _expires;

  String? _contentType;

  late Map<String, dynamic> _params;

  late int _state;

  late Dialog? _dialog;

  DateTime? _expires_timestamp;

  Timer? _expires_timer;

  late bool _terminated;

  Timer? _unsubscribe_timeout_timer;

  late Map<String, dynamic> _data;

  late String _event_name;

  bool? _event_id;

  late List<dynamic> _headers;

  late List<Map<String, dynamic>> _queue;

  /**
   * Expose C object.
   */
  static C getC() {
    return C();
  }

  void onRequestTimeout() {
    _dialogTerminated(C.SUBSCRIBE_RESPONSE_TIMEOUT);
  }

  void onTransportError() {
    _dialogTerminated(C.SUBSCRIBE_TRANSPORT_ERROR);
  }

  /**
   * Dialog callback.
   */
  void receiveRequest(IncomingRequest request) {
    if (request.method != SipMethod.NOTIFY) {
      logger.warn('received non-NOTIFY request');
      request.reply(405);

      return;
    }

    // RFC 6665 8.2.1. Check if event header matches.
    dynamic eventHeader = request.parseHeader('Event');

    if (!eventHeader) {
      logger.warn('missed Event header');
      request.reply(400);
      _dialogTerminated(C.RECEIVE_BAD_NOTIFY);

      return;
    }

    dynamic eventName = eventHeader.event;
    bool eventId = eventHeader.params && eventHeader.params.id;

    if (eventName != _event_name || eventId != _event_id) {
      logger.warn('Event header does not match SUBSCRIBE');
      request.reply(489);
      _dialogTerminated(C.RECEIVE_BAD_NOTIFY);

      return;
    }

    // Process Subscription-State header.
    dynamic subsState = request.parseHeader('subscription-state');

    if (!subsState) {
      logger.warn('missed Subscription-State header');
      request.reply(400);
      _dialogTerminated(C.RECEIVE_BAD_NOTIFY);

      return;
    }

    request.reply(200);

    int newState = _stateStringToNumber(subsState.state);
    int prevState = _state;

    if (prevState != C.STATE_TERMINATED && newState != C.STATE_TERMINATED) {
      _state = newState;

      if (subsState.expires != null) {
        int expires = subsState.expires;
        DateTime expiresTimestamp =
            DateTime.now().add(Duration(milliseconds: expires * 1000));
        int maxTimeDeviation = 2000;

        // Expiration time is shorter and the difference is not too small.
        if (_expires_timestamp!.difference(expiresTimestamp) >
            Duration(milliseconds: maxTimeDeviation)) {
          logger.debug('update sending re-SUBSCRIBE time');

          _scheduleSubscribe(expires);
        }
      }
    }

    if (prevState != C.STATE_PENDING && newState == C.STATE_PENDING) {
      logger.debug('emit "pending"');
      emit(EventPending());
    } else if (prevState != C.STATE_ACTIVE && newState == C.STATE_ACTIVE) {
      logger.debug('emit "active"');
      emit(EventActive());
    }

    String? body = request.body;

    // Check if the notify is final.
    bool isFinal = newState == C.STATE_TERMINATED;

    // Notify event fired only for notify with body.
    if (body != null) {
      dynamic contentType = request.getHeader('content-type');

      logger.debug('emit "notify"');
      emit(EventNotify(isFinal, request, body, contentType));
    }

    if (isFinal) {
      dynamic reason = subsState.reason;
      dynamic retryAfter = null;

      if (subsState.params && subsState.params['retry-after'] != null) {
        retryAfter = parseInt(subsState.params['retry-after'], 10);
      }

      _dialogTerminated(C.RECEIVE_FINAL_NOTIFY, reason, retryAfter);
    }
  }

  /**
   * User API
   */

  /** 
   * Send the initial (non-fetch)  and subsequent subscribe.
   * @param {string} body - subscribe request body.
   */
  void subscribe([String? body]) {
    logger.debug('subscribe()');

    if (_state == C.STATE_INIT) {
      _sendInitialSubscribe(body, _headers);
    } else {
      _sendSubsequentSubscribe(body, _headers);
    }
  }

  /** 
   * terminate. 
   * Send un-subscribe or fetch-subscribe (with Expires: 0).
   * @param {string} body - un-subscribe request body
   */
  void terminate([String? body]) {
    logger.debug('terminate()');

    // Prevent duplication un-subscribe sending.
    if (_terminated) {
      return;
    }
    _terminated = true;

    // Set header Expires: 0.
    List<dynamic> headers = _headers.map((dynamic header) {
      return header.startsWith('Expires') ? 'Expires: 0' : header;
    }).toList();

    if (_state == C.STATE_INIT) {
      // fetch-subscribe - initial subscribe with Expires: 0.
      _sendInitialSubscribe(body, headers);
    } else {
      _sendSubsequentSubscribe(body, headers);
    }

    // Waiting for the final notify for a while.
    int final_notify_timeout = 30000;

    _unsubscribe_timeout_timer = setTimeout(() {
      _dialogTerminated(C.UNSUBSCRIBE_TIMEOUT);
    }, final_notify_timeout);
  }

  /**
   * Private API.
   */
  void _sendInitialSubscribe(String? body, List<dynamic> headers) {
    if (body != null) {
      if (_contentType == null) {
        throw TypeError('content_type is undefined');
      }

      headers = headers.slice(0);
      headers.add('Content-Type: $_contentType');
    }

    _state = C.STATE_NOTIFY_WAIT;

    OutgoingRequest request = OutgoingRequest(SipMethod.SUBSCRIBE,
        _ua.normalizeTarget(_target), _ua, _params, headers, body);

    EventManager handler = EventManager();

    handler.on(EventOnReceiveResponse(), (EventOnReceiveResponse response) {
      _receiveSubscribeResponse(response.response);
    });

    handler.on(EventOnRequestTimeout(), (EventOnRequestTimeout timeout) {
      onRequestTimeout();
    });

    handler.on(EventOnTransportError(), (EventOnTransportError event) {
      onTransportError();
    });

    RequestSender request_sender = RequestSender(_ua, request, handler);

    request_sender.send();
  }

  void _receiveSubscribeResponse(IncomingResponse? response) {
    if (response == null) {
      throw ArgumentError('Incoming response was null');
    }
    if (response.status_code >= 200 && response.status_code! < 300) {
      // Create dialog
      if (_dialog == null) {
        try {
          Dialog dialog = Dialog(RTCSession(ua), response, 'UAC');
          _dialog = dialog;
        } catch (e) {
          logger.warn(e.toString());
          _dialogTerminated(C.SUBSCRIBE_BAD_OK_RESPONSE);

          return;
        }

        logger.debug('emit "accepted"');
        emit(EventAccepted());

        // Subsequent subscribes saved in the queue until dialog created.
        for (Map<String, dynamic> sub in _queue) {
          logger.debug('dequeue subscribe');

          _sendSubsequentSubscribe(sub['body'], sub['headers']);
        }
      }

      // Check expires value.
      dynamic expires_value = response.getHeader('expires');

      if (expires_value != 0 && !expires_value) {
        logger.warn('response without Expires header');

        // RFC 6665 3.1.1 subscribe OK response must contain Expires header.
        // Use workaround expires value.
        expires_value = '900';
      }

      int? expires = parseInt(expires_value, 10);

      if (expires! > 0) {
        _scheduleSubscribe(expires);
      }
    } else if (response.status_code == 401 || response.status_code == 407) {
      _dialogTerminated(C.SUBSCRIBE_FAILED_AUTHENTICATION);
    } else if (response.status_code >= 300) {
      _dialogTerminated(C.SUBSCRIBE_NON_OK_RESPONSE);
    }
  }

  void _sendSubsequentSubscribe(Object? body, List<dynamic> headers) {
    if (_state == C.STATE_TERMINATED) {
      return;
    }

    if (_dialog == null) {
      logger.debug('enqueue subscribe');

      _queue.add(<String, dynamic>{'body': body, 'headers': headers.slice(0)});

      return;
    }

    if (body != null) {
      if (_contentType == null) {
        throw TypeError('content_type is undefined');
      }

      headers = headers.slice(0);
      headers.add('Content-Type: $_contentType');
    }

    _dialog!.sendRequest(SipMethod.SUBSCRIBE, <String, dynamic>{
      'body': body,
      'extraHeaders': headers,
      'eventHandlers': <String, dynamic>{
        'onRequestTimeout': () {
          onRequestTimeout();
        },
        'onTransportError': () {
          onTransportError();
        },
        'onSuccessResponse': (IncomingResponse response) {
          _receiveSubscribeResponse(response);
        },
        'onErrorResponse': (IncomingResponse response) {
          _receiveSubscribeResponse(response);
        },
        'onDialogError': (IncomingResponse response) {
          _receiveSubscribeResponse(response);
        }
      }
    });
  }

  void _dialogTerminated(int terminationCode,
      [String? reason, int? retryAfter]) {
    // To prevent duplicate emit terminated event.
    if (_state == C.STATE_TERMINATED) {
      return;
    }

    _state = C.STATE_TERMINATED;

    // Clear timers.
    clearTimeout(_expires_timer);
    clearTimeout(_unsubscribe_timeout_timer);

    if (_dialog != null) {
      _dialog!.terminate();
      _dialog = null;
    }

    logger.debug('emit "terminated" code=$terminationCode');
    emit(EventTerminated(terminationCode, reason, retryAfter));
  }

  void _scheduleSubscribe(int expires) {
    /*
      If the expires time is less than 140 seconds we do not support Chrome intensive timer throttling mode. 
      In this case, the re-subscribe is sent 5 seconds before the subscription expiration.

      When Chrome is in intensive timer throttling mode, in the worst case, 
	  the timer will be 60 seconds late.
      We give the server 10 seconds to make sure it will execute the command even if it is heavily loaded. 
      As a result, we order the time no later than 70 seconds before the subscription expiration.
      Resulting time calculated as half time interval + (half interval - 70) * random.

      E.g. expires is 140, re-subscribe will be ordered to send in 70 seconds.
	       expires is 600, re-subscribe will be ordered to send in 300 + (0 .. 230) seconds.
	 */

    int timeout = (expires >= 140
            ? (expires * 1000 / 2) +
                Math.floor(((expires / 2) - 70) * 1000 * Math.random())
            : (expires * 1000) - 5000)
        .toInt();

    _expires_timestamp =
        DateTime.now().add(Duration(milliseconds: expires * 1000));

    logger.debug(
        'next SUBSCRIBE will be sent in ${Math.floor(timeout / 1000)} sec');

    clearTimeout(_expires_timer);
    _expires_timer = setTimeout(() {
      _expires_timer = null;
      _sendSubsequentSubscribe(null, _headers);
    }, timeout);
  }

  int _stateStringToNumber(String? strState) {
    switch (strState) {
      case 'pending':
        return C.STATE_PENDING;
      case 'active':
        return C.STATE_ACTIVE;
      case 'terminated':
        return C.STATE_TERMINATED;
      case 'init':
        return C.STATE_INIT;
      case 'notify_wait':
        return C.STATE_NOTIFY_WAIT;
      default:
        throw TypeError('wrong state value');
    }
  }
}
