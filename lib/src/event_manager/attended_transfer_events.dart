import 'events.dart';

/// Event emitted when an attended transfer starts processing.
///
/// This event is fired when the REFER request for attended transfer
/// has been sent and the transfer process has begun.
class EventAttendedTransferTrying extends EventType {
  EventAttendedTransferTrying({this.callId, this.request});

  /// The Call-ID of the call being transferred.
  String? callId;

  /// The original REFER request.
  dynamic request;
}

/// Event emitted when an attended transfer is in progress.
///
/// This event indicates that the transfer target is being contacted
/// and the transfer is proceeding.
class EventAttendedTransferProgress extends EventType {
  EventAttendedTransferProgress({this.callId, this.statusLine, this.request});

  /// The Call-ID of the call being transferred.
  String? callId;

  /// The SIP status line from the NOTIFY response.
  String? statusLine;

  /// The NOTIFY request with progress information.
  dynamic request;
}

/// Event emitted when an attended transfer is successfully accepted.
///
/// This event indicates that the transfer target has accepted the
/// transferred call and the parties are now connected.
class EventAttendedTransferAccepted extends EventType {
  EventAttendedTransferAccepted({this.callId, this.statusLine, this.request});

  /// The Call-ID of the call that was transferred.
  String? callId;

  /// The SIP status line from the NOTIFY response.
  String? statusLine;

  /// The NOTIFY request with acceptance information.
  dynamic request;
}

/// Event emitted when an attended transfer fails.
///
/// This event indicates that the transfer could not be completed.
/// The original call may still be active depending on when the failure occurred.
class EventAttendedTransferFailed extends EventType {
  EventAttendedTransferFailed(
      {this.callId, this.statusLine, this.request, this.cause});

  /// The Call-ID of the call that failed to transfer.
  String? callId;

  /// The SIP status line from the NOTIFY response.
  String? statusLine;

  /// The NOTIFY request with failure information.
  dynamic request;

  /// The error cause if available.
  ErrorCause? cause;
}
