import '../message.dart';
import 'events.dart';

class EventNewMessage extends EventType {
  EventNewMessage({this.message, this.originator, this.request});
  dynamic request;
  String? originator;
  Message? message;
}
