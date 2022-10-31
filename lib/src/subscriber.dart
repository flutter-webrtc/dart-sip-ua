import 'dart:async';

import 'package:collection/collection.dart';

import 'constants.dart';
import 'dialog.dart';
import 'event_manager/event_manager.dart';
import 'event_manager/internal_events.dart';
import 'event_manager/subscriber_events.dart';
import 'exceptions.dart';
import 'grammar.dart';
import 'logger.dart';
import 'request_sender.dart';
import 'sip_message.dart';
import 'timers.dart';
import 'ua.dart';
import 'utils.dart';

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

class Subscriber extends EventManager implements Owner {
  Subscriber(this.ua, this._target, String eventName, String accept,
      [int expires = 900,
      String? contentType,
      String? allowEvents,
      Map<String, dynamic> requestParams = const <String, dynamic>{},
      List<String> extraHeaders = const <String>[]]) {
    logger.d('new');

    _expires = expires;

    // Used to subscribe with body.
    _contentType = contentType;

    _params = Map<String, dynamic>.from(requestParams);

    _params['from_tag'] = newTag();

    _params['to_tag'] = null;

    _params['call_id'] = createRandomToken(20);

    //if (_params['cseq'] == null) {
    //  _params['cseq'] = Math.floor((Math.random() * 10000) + 1);
    //}

    dynamic parsed = Grammar.parse(eventName, 'Event');

    if (parsed == -1) {
      throw TypeError('eventName - wrong format');
    }

    _event_name = parsed.event;
    // this._event_id = parsed.params && parsed.params.id;
    _event_id = parsed.params['id'];

    String eventValue = _event_name;

    if (_event_id != null) {
      eventValue += ';id=$_event_id';
    }

    _headers = cloneArray(extraHeaders);

    _headers.addAll(<String>['Event: $eventValue', 'Expires: $_expires']);

    if (!_headers.any((dynamic element) => element.startsWith('Contact'))) {
      String contact = 'Contact: ${ua.contact.toString()}';

      _headers.add(contact);
    }

    if (allowEvents != null) {
      _headers.add('Allow-Events: $allowEvents');
    }

    receiveRequest = receiveNotifyRequest;
  }
  String? _id;

  final String _target;

  late int _expires;

  String? _contentType;

  late Map<String, dynamic> _params;

  int _state = C.STATE_INIT;

  Dialog? _dialog;

  DateTime? _expires_timestamp;

  Timer? _expires_timer;

  bool _terminated = false;

  Timer? _unsubscribe_timeout_timer;

  late Map<String, dynamic> _data;

  late String _event_name;

  num? _event_id;

  late List<dynamic> _headers;

  // To enqueue subscribes created before receive initial subscribe OK.
  final List<Map<String, dynamic>> _queue = <Map<String, dynamic>>[];

  @override
  late Function(IncomingRequest p1) receiveRequest;

  @override
  UA ua;
  String? get id => _id;

  @override
  int get status => _state;

  @override
  int get TerminatedCode => C.STATE_TERMINATED;

  void onRequestTimeout() {
    _dialogTerminated(C.SUBSCRIBE_RESPONSE_TIMEOUT);
  }

  /**
   * User API
   */

  void onTransportError() {
    _dialogTerminated(C.SUBSCRIBE_TRANSPORT_ERROR);
  }

  /**
   * Dialog callback.
   */
  void receiveNotifyRequest(IncomingRequest request) {
    if (request.method != SipMethod.NOTIFY) {
      logger.w('received non-NOTIFY request');
      request.reply(405);

      return;
    }

    // RFC 6665 8.2.1. Check if event header matches.
    dynamic eventHeader = request.parseHeader('Event');

    if (eventHeader == null) {
      logger.w('missed Event header');
      request.reply(400);
      _dialogTerminated(C.RECEIVE_BAD_NOTIFY);

      return;
    }

    dynamic eventName = eventHeader.event;
    num? eventId = eventHeader.params['id'];

    if (eventName != _event_name || eventId != _event_id) {
      logger.w('Event header does not match SUBSCRIBE');
      request.reply(489);
      _dialogTerminated(C.RECEIVE_BAD_NOTIFY);

      return;
    }

    // Process Subscription-State header.
    dynamic subsState = request.parseHeader('subscription-state');

    if (subsState == null) {
      logger.w('missed Subscription-State header');
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
          logger.d('update sending re-SUBSCRIBE time');

          _scheduleSubscribe(expires);
        }
      }
    }

    if (prevState != C.STATE_PENDING && newState == C.STATE_PENDING) {
      logger.d('emit "pending"');
      emit(EventPending());
    } else if (prevState != C.STATE_ACTIVE && newState == C.STATE_ACTIVE) {
      logger.d('emit "active"');
      emit(EventActive());
    }

    String? body = request.body;

    // Check if the notify is final.
    bool isFinal = newState == C.STATE_TERMINATED;

    // Notify event fired only for notify with body.
    if (body != null) {
      dynamic contentType = request.getHeader('content-type');

      logger.d('emit "notify"');
      emit(EventNotify(
          isFinal: isFinal,
          request: request,
          body: body,
          contentType: contentType));
    }

    if (isFinal) {
      dynamic reason = subsState.reason;
      dynamic retryAfter = null;

      if (subsState.params != null && subsState.params['retry-after'] != null) {
        retryAfter = int.tryParse(subsState.params['retry-after'], radix: 10);
      }

      _dialogTerminated(C.RECEIVE_FINAL_NOTIFY, reason, retryAfter);
    }
  }

  /** 
   * Send the initial (non-fetch)  and subsequent subscribe.
   * @param {string} body - subscribe request body.
   */
  void subscribe([String? target, String? body]) {
    logger.d('subscribe()');

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
  void terminate(String? body) {
    logger.d('terminate()');

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
      _dialog?.terminate();
      _dialog = null;
    }

    logger.d('emit "terminated" code=$terminationCode');
    emit(EventTerminated(
        TerminationCode: terminationCode,
        reason: reason,
        retryAfter: retryAfter));
  }

  void _handlePresence(EventNotify event) {
    emit(event);
  }

  void _receiveSubscribeResponse(IncomingResponse? response) {
    if (response == null) {
      throw ArgumentError('Incoming response was null');
    }

    if (response.status_code >= 200 && response.status_code < 300) {
      // Create dialog
      if (_dialog == null) {
        _id = response.call_id!;
        try {
          Dialog dialog = Dialog(this, response, 'UAC');
          _dialog = dialog;
        } catch (e) {
          logger.w(e.toString());
          _dialogTerminated(C.SUBSCRIBE_BAD_OK_RESPONSE);

          return;
        }

        logger.d('emit "accepted"');
        emit(EventAccepted());

        // Subsequent subscribes saved in the queue until dialog created.
        for (Map<String, dynamic> sub in _queue) {
          logger.d('dequeue subscribe');

          _sendSubsequentSubscribe(sub['body'], sub['headers']);
        }
      } else {
        ua.destroySubscriber(this);
        _id = response.call_id;
        ua.newSubscriber(sub: this);
      }

      ua.newSubscriber(sub: this);

      // Check expires value.
      String? expires_value = response.getHeader('Expires');

      if (expires_value != null &&
          expires_value == '' &&
          expires_value == '0') {
        logger.w('response without Expires header');

        // RFC 6665 3.1.1 subscribe OK response must contain Expires header.
        // Use workaround expires value.
        expires_value = '900';
      }

      int? expires = int.tryParse(expires_value!, radix: 10);

      if (expires != null && expires > 0) {
        _scheduleSubscribe(expires);
      }
    } else if (response.status_code == 401 || response.status_code == 407) {
      _dialogTerminated(C.SUBSCRIBE_FAILED_AUTHENTICATION);
    } else if (response.status_code >= 300) {
      _dialogTerminated(C.SUBSCRIBE_NON_OK_RESPONSE);
    }
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

    num timeout = expires / 2;

    _expires_timestamp = DateTime.now().add(Duration(seconds: expires));

    logger.d('next SUBSCRIBE will be sent in $timeout sec');

    clearTimeout(_expires_timer);

    _expires_timer = setTimeout(() {
      _expires_timer = null;
      _sendSubsequentSubscribe(null, _headers);
    }, timeout.toInt() * 1000);
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
        ua.normalizeTarget(_target)!, ua, _params, headers, body);

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

    RequestSender request_sender = RequestSender(ua, request, handler);

    request_sender.send();
  }

  void _sendSubsequentSubscribe(String? body, List<dynamic> headers) {
    if (_state == C.STATE_TERMINATED) {
      return;
    }

    if (_dialog == null) {
      logger.d('enqueue subscribe');

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

    EventManager manager = EventManager();
    manager.on(EventOnReceiveResponse(), (EventOnReceiveResponse response) {
      _receiveSubscribeResponse(response.response);
    });

    manager.on(EventOnRequestTimeout(), (EventOnRequestTimeout timeout) {
      onRequestTimeout();
    });

    manager.on(EventOnTransportError(), (EventOnTransportError event) {
      onTransportError();
    });

    OutgoingRequest request = OutgoingRequest(SipMethod.SUBSCRIBE,
        ua.normalizeTarget(_target)!, ua, _params, headers, body);

    RequestSender request_sender = RequestSender(ua, request, manager);

    request_sender.send();

    _dialog?.sendRequest(SipMethod.SUBSCRIBE, <String, dynamic>{
      'body': body,
      'extraHeaders': headers,
      'eventHandlers': manager,
    });
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

  /**
   * Expose C object.
   */
  static C getC() {
    return C();
  }
}

class SubscriptionId {
  SubscriptionId(this.target, this.event);
  String target;
  String event;
}
