import '../message.dart';
import 'events.dart';

class EventNewMessage extends EventType {
  dynamic request;
  String originator;
  Message message;
  EventNewMessage({this.message, this.originator, this.request});
}
