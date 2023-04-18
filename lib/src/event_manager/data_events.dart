import 'package:sip_ua/src/event_manager/event_manager.dart';

class EventReceivedData extends EventType {
  EventReceivedData({this.data});

  dynamic data;
}
