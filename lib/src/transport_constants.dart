/**
 * Constants
 */
class C {
  // Transport status.
  static const int STATUS_CONNECTED = 0;
  static const int STATUS_CONNECTING = 1;
  static const int STATUS_DISCONNECTED = 2;

  // Socket status.
  static const int SOCKET_STATUS_READY = 0;
  static const int SOCKET_STATUS_ERROR = 1;

  // Recovery options.
  static const Map<String, int> recovery_options = <String, int>{
    'min_interval': 2, // minimum interval in seconds between recover attempts
    'max_interval': 30 // maximum interval in seconds between recover attempts
  };
}
