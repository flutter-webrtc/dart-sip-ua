/// each EventType class can implement this method and the EventManager will call it before
/// delivering an event, thus ensuring good quality events with a fail early approach.
abstract class EventType {
  void sanityCheck() {}
}

/// All of the following Event classes are named exactly the same as the strings that the old code used
/// except that they are all prefixed with Event. ie. "stateChanged" is EventStateChanged
///
/// You will see a lot of commented out fields, these fields are not referenced any where in the code.
/// In a future update I'd suggest removing them and removing the parameters associated with them and
/// thus remove a lot of unneeded code.
///
/// I've tried to infer types to help with future debugging, but unfortunately the types of "response"
/// and "request" are many and share no common hierarchy so they have
/// to remain dynamic in many places for now.
///
/// These changes will make it much easier to reason about where Events go to and come from, as well as
/// exactly what fields are available without the need to actually run the code.

/// A general error cause class.
class ErrorCause {
  ErrorCause({this.status_code, this.cause, this.reason_phrase});
  @override
  String toString() {
    return 'Code: [$status_code], Cause: $cause, Reason: $reason_phrase';
  }

  int? status_code;
  String? cause;
  String? reason_phrase;
}
