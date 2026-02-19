import 'log_level.dart';

class LogEvent {
  final Level level;
  final dynamic message;
  final Object? error;
  final StackTrace? stackTrace;

  /// Time when this log was created.
  final DateTime time;

  LogEvent(
    this.level,
    this.message, {
    DateTime? time,
    this.error,
    this.stackTrace,
  }) : time = time ?? DateTime.now();
}
