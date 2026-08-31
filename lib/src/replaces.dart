/// Represents the SIP Replaces header data structure used in attended transfer.
///
/// The Replaces header is defined in RFC 3891 and is used in attended transfer
/// scenarios (RFC 5589) to identify which existing SIP dialog should be replaced
/// when establishing a new call.
///
/// A SIP dialog is uniquely identified by three components:
/// - [callId]: The Call-ID header value from the original INVITE
/// - [fromTag]: The tag parameter from the From header
/// - [toTag]: The tag parameter from the To header
///
/// Example usage:
/// ```dart
/// final replaces = Replaces(
///   callId: 'abc123@example.com',
///   fromTag: 'tag-from-party-a',
///   toTag: 'tag-from-party-c',
/// );
/// ```
class Replaces {
  /// Creates a new [Replaces] instance with the required dialog identifiers.
  ///
  /// All three parameters are required as they together uniquely identify
  /// a SIP dialog that should be replaced during attended transfer.
  Replaces({
    required this.callId,
    required this.fromTag,
    required this.toTag,
  });

  /// The Call-ID header value from the SIP dialog to be replaced.
  ///
  /// This is the unique identifier for the call/session.
  final String callId;

  /// The tag parameter from the From header of the dialog to be replaced.
  ///
  /// This identifies the initiator's leg of the dialog.
  // ignore: non_constant_identifier_names
  final String fromTag;

  /// The tag parameter from the To header of the dialog to be replaced.
  ///
  /// This identifies the responder's leg of the dialog.
  // ignore: non_constant_identifier_names
  final String toTag;

  // Getters for internal use by refer_subscriber.dart (uses underscore naming)
  // ignore: non_constant_identifier_names
  String get call_id => callId;
  // ignore: non_constant_identifier_names
  String get from_tag => fromTag;
  // ignore: non_constant_identifier_names
  String get to_tag => toTag;

  @override
  String toString() {
    return 'Replaces(callId: $callId, fromTag: $fromTag, toTag: $toTag)';
  }

  /// Builds the encoded Replaces parameter for a Refer-To URI.
  ///
  /// Returns a properly formatted and URI-encoded string that can be
  /// appended to a Refer-To header.
  ///
  /// Format: `Call-ID;to-tag=xxx;from-tag=yyy` (URI encoded)
  String toEncodedString() {
    String replaces = callId;
    replaces += ';to-tag=$toTag';
    replaces += ';from-tag=$fromTag';
    return Uri.encodeComponent(replaces);
  }
}
