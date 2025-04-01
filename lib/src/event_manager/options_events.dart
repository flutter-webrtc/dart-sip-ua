import '../enums.dart';
import '../options.dart';
import 'events.dart';

class EventNewOptions extends EventType {
  EventNewOptions({this.message, this.originator, this.request});
  dynamic request;
  Originator? originator;
  Options? message;
}
