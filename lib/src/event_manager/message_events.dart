import '../enums.dart';
import '../message.dart';
import 'events.dart';

class EventNewMessage extends EventType {
  EventNewMessage({this.message, this.originator, this.request});
  dynamic request;
  Originator? originator;
  Message? message;
}
