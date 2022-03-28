import 'package:sip_ua/src/sip_message.dart';

import 'events.dart';

class EventTerminated extends EventType {
  EventTerminated({this.terminationCode, this.sendFinalNotify});
  int? terminationCode;
  bool? sendFinalNotify;
}

class EventSubscribe extends EventType {
  EventSubscribe(
      {this.isUnsubscribe, this.request, this.body, this.content_type});
  bool? isUnsubscribe;
  IncomingRequest? request;
  String? body;
  String? content_type;
}
