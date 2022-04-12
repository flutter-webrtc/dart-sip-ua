import '../options.dart';
import 'events.dart';

class EventNewOptions extends EventType {
  EventNewOptions({this.message, this.originator, this.request});
  dynamic request;
  String? originator;
  Options? message;
}
