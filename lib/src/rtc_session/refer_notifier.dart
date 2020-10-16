import '../constants.dart' as DartSIP_C;
import '../constants.dart';
import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../logger.dart';
import '../rtc_session.dart' as rtc;

class C {
  static const String event_type = 'refer';
  static const String body_type = 'message/sipfrag;version=2.0';
  static const int expires = 300;
}

class ReferNotifier {
  rtc.RTCSession _session;
  String _id;
  int _expires;
  bool _active;

  ReferNotifier(rtc.RTCSession session, String id, [int expires]) {
    _session = session;
    _id = id;
    _expires = expires ?? C.expires;
    _active = true;

    // The creation of a Notifier results in an immediate NOTIFY.
    notify(100);
  }

  void notify(int code, [String reason]) {
    logger.debug('notify()');

    if (_active == false) {
      return;
    }

    reason = reason ?? DartSIP_C.REASON_PHRASE[code] ?? '';

    String state;

    if (code >= 200) {
      state = 'terminated;reason=noresource';
    } else {
      state = 'active;expires=${_expires}';
    }

    EventManager handlers = EventManager();
    handlers.on(EventOnErrorResponse(), (EventOnErrorResponse event) {
      // If a negative response is received, subscription is canceled.
      _active = false;
    });

    // Put this in a try/catch block.
    _session.sendRequest(SipMethod.NOTIFY, {
      'extraHeaders': [
        'Event: ${C.event_type};id=${_id}',
        'Subscription-State: ${state}',
        'Content-Type: ${C.body_type}'
      ],
      'body': 'SIP/2.0 ${code} ${reason}',
      'eventHandlers': handlers
    });
  }
}
