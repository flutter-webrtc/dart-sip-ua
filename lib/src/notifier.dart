import 'dart:async';

import 'package:collection/collection.dart';
import 'package:sip_ua/src/constants.dart';
import 'package:sip_ua/src/dialog.dart';
import 'package:sip_ua/src/event_manager/notifier_events.dart';
import 'package:sip_ua/src/exceptions.dart';
import 'package:sip_ua/src/logger.dart';
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
  static const int NOTIFY_RESPONSE_TIMEOUT = 0;
  static const int NOTIFY_TRANSPORT_ERROR = 1;
  static const int NOTIFY_NON_OK_RESPONSE = 2;
  static const int NOTIFY_FAILED_AUTHENTICATION = 3;
  static const int SEND_FINAL_NOTIFY = 4;
  static const int RECEIVE_UNSUBSCRIBE = 5;
  static const int SUBSCRIPTION_EXPIRED = 6;

  // Notifier states
  static const int STATE_PENDING = 0;
  static const int STATE_ACTIVE = 1;
  static const int STATE_TERMINATED = 2;
}

class Notifier extends EventManager {
  Notifier(this.ua, this._initialSubscribe, this._content_type,
      [bool pending = false,
      List<String>? extraHeaders = null,
      String? allowEvents = null]) {
    logger.debug('new');
    if (!_initialSubscribe.hasHeader('contact')) {
      throw TypeError('subscribe - no contact header');
    }
    _state = pending ? C.STATE_PENDING : C.STATE_ACTIVE;

    _terminated_reason = null;
    _terminated_retry_after = null;

    String eventName = _initialSubscribe.getHeader('event');

    _expires = parseInt(_initialSubscribe.getHeader('expires'), 10)!;
    _headers = cloneArray(extraHeaders);
    _headers.add('Event: $eventName');

    // Use contact from extraHeaders or create it.
    String? c = _headers
        .firstWhereOrNull((String header) => header.startsWith('Contact'));
    if (c == null) {
      _contact = 'Contact: ${ua.contact.toString()}';

      _headers.add(_contact);
    } else {
      _contact = c;
    }

    if (allowEvents != null) {
      _headers.add('Allow-Events: $allowEvents');
    }

    _target = _initialSubscribe.from?.uri?.user;

    _initialSubscribe.to_tag = newTag();

    // Create dialog for normal and fetch-subscribe.
    Dialog dialog = Dialog(this, _initialSubscribe, 'UAS');

    _dialog = dialog;

    if (_expires > 0) {
      // Set expires timer and time-stamp.
      _setExpiresTimer();
    }
  }

  late int _state;
  String? _terminated_reason;
  num? _terminated_retry_after;
  late Map<String, dynamic> data;
  late int _expires;
  late List<dynamic> _headers;
  late String _contact;
  String? _target;

  static C getC() {
    return C();
  }

  UA ua;
  final IncomingRequest _initialSubscribe;
  final String _content_type;
  DateTime? _expires_timestamp;
  Timer? _expires_timer;
  late Dialog? _dialog;

  /**
   * Dialog callback.
   * Called also for initial subscribe. 
   * Supported RFC 6665 4.4.3: initial fetch subscribe (with expires: 0).
   */
  void receiveRequest(IncomingRequest request) {
    if (request.method != SipMethod.NOTIFY) {
      request.reply(405);

      return;
    }

    if (request.hasHeader('expires')) {
      _expires = parseInt(request.getHeader('expires'), 10)!;
    } else {
      // RFC 6665 3.1.1, default expires value.
      _expires = 900;

      logger
          .debug('missing Expires header field, default value set: $_expires');
    }
    request.reply(200, null, <String>['Expires: $_expires', _contact]);

    String? body = request.body;
    String content_type = request.getHeader('content-type');
    bool is_unsubscribe = _expires == 0;

    if (!is_unsubscribe) {
      _setExpiresTimer();
    }

    logger.debug('emit "subscribe"');
    emit(EventSubscribe(is_unsubscribe, request, body, content_type));

    if (is_unsubscribe) {
      _dialogTerminated(C.RECEIVE_UNSUBSCRIBE);
    }
  }

  /**
   * User API
   */
  /**
   * Please call after creating the Notifier instance and setting the event handlers.
   */
  void start() {
    logger.debug('start()');

    receiveRequest(_initialSubscribe);
  }

  /**
   * Switch pending dialog state to active.
   */
  void setActiveState() {
    logger.debug('setActiveState()');

    if (_state == C.STATE_PENDING) {
      _state = C.STATE_ACTIVE;
    }
  }

  /**
   *  Send the initial and subsequent notify request.
   *  @param {string} body - notify request body.
   */
  void notify([String? body = null]) {
    logger.debug('notify()');

    // Prevent send notify after final notify.
    if (_dialog == null) {
      logger.warn('final notify has sent');

      return;
    }

    String subs_state = _stateNumberToString(_state);

    if (_state != C.STATE_TERMINATED) {
      num expires = Math.floor(
          (_expires_timestamp!.subtract(DateTime.now())).millisecond / 1000);

      if (expires < 0) {
        expires = 0;
      }

      subs_state += ';expires=$expires';
    } else {
      if (_terminated_reason != null) {
        subs_state += ';reason=$_terminated_reason';
      }
      if (_terminated_retry_after != null) {
        subs_state += ';retry-after=$_terminated_retry_after';
      }
    }

    ListSlice<dynamic> headers = _headers.slice(0);

    headers.add('Subscription-State: $subs_state');

    if (body != null) {
      headers.add('Content-Type: $_content_type');
    }

    _dialog!.sendRequest(SipMethod.NOTIFY, <String, dynamic>{
      'body': body,
      'extraHeaders': headers,
      'eventHandlers': <String, dynamic>{
        'onRequestTimeout': () {
          _dialogTerminated(C.NOTIFY_RESPONSE_TIMEOUT);
        },
        'onTransportError': () {
          _dialogTerminated(C.NOTIFY_TRANSPORT_ERROR);
        },
        'onErrorResponse': (IncomingResponse response) {
          if (response.status_code == 401 || response.status_code == 407) {
            _dialogTerminated(C.NOTIFY_FAILED_AUTHENTICATION);
          } else {
            _dialogTerminated(C.NOTIFY_NON_OK_RESPONSE);
          }
        },
        'onDialogError': () {
          _dialogTerminated(C.NOTIFY_NON_OK_RESPONSE);
        }
      }
    });
  }

  /**
   *  Terminate. (Send the final NOTIFY request).
   * 
   * @param {string} body - Notify message body.
   * @param {string} reason - Set Subscription-State reason parameter.
   * @param {number} retryAfter - Set Subscription-State retry-after parameter.
   */
  void terminate(
      [String? body = null, String? reason = null, num? retryAfter = null]) {
    logger.debug('terminate()');

    _state = C.STATE_TERMINATED;
    _terminated_reason = reason;
    _terminated_retry_after = retryAfter;

    notify(body);

    _dialogTerminated(C.SEND_FINAL_NOTIFY);
  }

  /**
   * Get dialog state. 
   */
  int get state {
    return _state;
  }

  /**
   * Get dialog id.
   */
  Id? get id {
    return _dialog?.id;
  }

  /**
   * Private API
   */
  void _dialogTerminated(int termination_code) {
    if (_dialog == null) {
      return;
    }

    _state = C.STATE_TERMINATED;
    clearTimeout(_expires_timer);

    if (_dialog != null) {
      _dialog!.terminate();
      _dialog = null;
    }

    bool send_final_notify = termination_code == C.SUBSCRIPTION_EXPIRED;

    logger.debug(
        'emit "terminated" code=$termination_code, send final notify=$send_final_notify');
    emit(EventTerminated(termination_code, send_final_notify));
  }

  void _setExpiresTimer() {
    _expires_timestamp =
        DateTime.now().add(Duration(milliseconds: _expires * 1000));

    clearTimeout(_expires_timer);
    _expires_timer = setTimeout(() {
      if (_dialog == null) {
        return;
      }

      _terminated_reason = 'timeout';
      notify();
      _dialogTerminated(C.SUBSCRIPTION_EXPIRED);
    }, _expires * 1000);
  }

  String _stateNumberToString(int state) {
    switch (state) {
      case C.STATE_PENDING:
        return 'pending';
      case C.STATE_ACTIVE:
        return 'active';
      case C.STATE_TERMINATED:
        return 'terminated';
      default:
        throw TypeError('wrong state value');
    }
  }
}
