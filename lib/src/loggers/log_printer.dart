import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:io';
import 'package:intl/intl.dart';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../extensions/platform_extension.dart';
import './enum_helper.dart';
import './log_event.dart';
import './log_level.dart';
import './stack_trace.dart';

// ignore_for_file: avoid_print

class MyLogPrinter {
  late File file;
  final StreamController<String> _logBuffer = StreamController<String>();
  Timer? _flushTimer;
  final StringBuffer _pendingWrites = StringBuffer();
  bool _writeInProgress = false;

  // Track current log file date for automatic daily rotation
  DateTime? _currentLogDate;

  // Add line counter for periodic cleanup
  int _lineCount = 0;
  static const int _cleanupThreshold = 10000;

  String filePrefix;
  String statementPrefix;
  bool isInitialized = false;

  // Private constructor
  MyLogPrinter._private({this.filePrefix = '', this.statementPrefix = ''}) {
    if (PlatformExtension.isDesktop) {
      getApplicationDocumentsDirectory().then((appDir) {
        if (appDir.path.isNotEmpty) {
          _currentLogDate = DateTime.now();
          String fileName = getFileName(filePrefix: filePrefix);
          String pathName = Platform.isWindows ? "${appDir.path}\\$fileName" : "${appDir.path}/$fileName";
          file = File(pathName);
          print('$statementPrefix Application Log File Path: $pathName');
          isInitialized = true;

          // Set up log buffer processing
          _setupLogBufferProcessing();

          // Flush any initial statements
          if (initialStatement.isNotEmpty) {
            _logBuffer.add(initialStatement);
            initialStatement = "";
          }
          // Call manageLogs at startup
          manageLogs();
        }
      }, onError: (error, stackTrace) {
        print('MyLogPrinter Error: $error');
      });
    }
  }

  void _setupLogBufferProcessing() {
    // Set up a subscription to process log entries
    _logBuffer.stream.listen((logEntry) {
      _pendingWrites.write(logEntry);
      _processWrites();
    });

    // Set up periodic flush timer (every 500ms)
    _flushTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_pendingWrites.isNotEmpty) {
        _processWrites();
      }
    });
  }

  // Process pending writes to file
  Future<void> _processWrites() async {
    if (_writeInProgress || _pendingWrites.isEmpty) return;

    _writeInProgress = true;
    String dataToWrite = _pendingWrites.toString();
    _pendingWrites.clear();

    try {
      bool doesExist = await file.exists();
      if (doesExist == false) {
        await file.create(recursive: true);
      }

      // Use UTF-8 encoding explicitly
      await file.writeAsBytes(utf8.encode(dataToWrite), mode: FileMode.append, flush: true // Ensure data is written to disk
          );
    } catch (e) {
      print("Error writing to log file: $e");
      // Put content back in the buffer to retry
      _pendingWrites.write(dataToWrite);
    } finally {
      _writeInProgress = false;

      // Process any writes that came in while we were writing
      if (_pendingWrites.isNotEmpty) {
        // Use a small delay to prevent tight loops
        Timer(const Duration(milliseconds: 50), _processWrites);
      }
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    _logBuffer.close();
  }

  static final Map<String, MyLogPrinter> _instances = {};

  factory MyLogPrinter({String filePrefix = '', String statementPrefix = ''}) {
    if (!_instances.containsKey(filePrefix)) {
      _instances[filePrefix] = MyLogPrinter._private(filePrefix: filePrefix, statementPrefix: statementPrefix);
    }
    return _instances[filePrefix]!;
  }
  static final Map<Level, AnsiColor> levelColors = <Level, AnsiColor>{
    Level.debug: AnsiColor.none(),
    Level.info: AnsiColor.fg(12),
    Level.warning: AnsiColor.fg(208),
    Level.error: AnsiColor.fg(196),
  };

  String getFileName({String filePrefix = "", DateTime? forDate}) {
    DateTime now = forDate ?? DateTime.now();
    String year = now.year.toString();
    String month = now.month.toString().padLeft(2, '0');
    String day = now.day.toString().padLeft(2, '0');
    String hour = now.hour.toString().padLeft(2, '0');
    String result = "${filePrefix}_${year}_${month}_${day}_$hour";
    print(result); // Output ex: 2023_10_09_14
    return result;
  }

  bool colors = true;

  String initialStatement = "";
  Future<void> write(arg) async {
    try {
      const String lineTerminator = "\n"; // Always use \n for consistency
      if (isInitialized) {
        // Check if we've crossed midnight and need to rotate the log file
        await _checkAndRotateLogFile();

        _logBuffer.add("$arg$lineTerminator");
        _lineCount++;
        if (_lineCount >= _cleanupThreshold) {
          _performPeriodicCleanup();
        }
      } else {
        initialStatement += "$arg$lineTerminator";
      }
    } catch (e) {
      print("LogPrinter: Error buffering log entry ${e.toString()}");
    }
  }

  /// Checks if the date has changed and rotates to a new log file if needed
  Future<void> _checkAndRotateLogFile() async {
    final now = DateTime.now();

    // Check if we need to rotate (date has changed)
    if (_currentLogDate != null && (now.year != _currentLogDate!.year || now.month != _currentLogDate!.month || now.day != _currentLogDate!.day)) {
      await _rotateLogFile(now);
    }
  }

  /// Rotates to a new log file with the given date
  Future<void> _rotateLogFile(DateTime newDate) async {
    try {
      print('$statementPrefix Rotating log file from $_currentLogDate to $newDate');

      // Flush any pending writes before rotating
      if (_pendingWrites.isNotEmpty) {
        await _processWrites();
      }

      // Update the current log date
      _currentLogDate = newDate;

      // Create new file with new date
      final appDir = await getApplicationDocumentsDirectory();
      String fileName = getFileName(filePrefix: filePrefix, forDate: newDate);
      String pathName = Platform.isWindows ? "${appDir.path}\\$fileName" : "${appDir.path}/$fileName";
      file = File(pathName);

      print('$statementPrefix New log file path: $pathName');

      // Reset line count for the new file
      _lineCount = 0;

      // Clean up old logs after rotation
      manageLogs();
    } catch (e) {
      print('$statementPrefix Error rotating log file: $e');
    }
  }

  List<String> log(LogEvent event) {
    if (EnumHelper.getIndexOf(Level.values, Level.trace) > EnumHelper.getIndexOf(Level.values, event.level)) {
      // don't log events where the log level is set higher
      return <String>[];
    }
    DateFormat formatter = DateFormat('yyyy-MM-dd HH:mm:ss.');
    DateTime now = DateTime.now();
    String formattedDate = formatter.format(now) + now.millisecond.toString().padLeft(3, '0');

    AnsiColor color = _getLevelColor(event.level);

    StackTraceNJ frames = StackTraceNJ();
    int i = 0;
    int depth = 0;
    if (frames.frames != null) {
      for (Stackframe frame in frames.frames!) {
        i++;
        String path2 = frame.sourceFile.path;
        if (!path2.contains(getFileName()) && !path2.contains('sip_logger.dart')) {
          depth = i - 1;
          break;
        }
      }
    }

    String formattedMsg = '[$formattedDate] ${event.level} ${StackTraceNJ(skipFrames: depth).formatStackTrace(methodCount: 1)} ::: ${event.message}';
    print(color(formattedMsg));
    write(formattedMsg);

    if (event.error != null) {
      String errorMsg = '${event.error}';
      print(errorMsg);
      write(errorMsg);
    }

    if (event.stackTrace != null) {
      String stackTraceMsg;
      if (event.stackTrace.runtimeType == StackTraceNJ) {
        StackTraceNJ st = event.stackTrace as StackTraceNJ;
        stackTraceMsg = '$st';
      } else {
        stackTraceMsg = '${event.stackTrace}';
      }
      print(color(stackTraceMsg));
      write(stackTraceMsg);
    }

    return <String>[];
  }

  AnsiColor _getLevelColor(Level level) {
    if (colors) {
      return levelColors[level] ?? AnsiColor.none();
    } else {
      return AnsiColor.none();
    }
  }

  void manageLogs() async {
    final logDir = await getApplicationDocumentsDirectory();
    final oldLogFiles = await getLogsByDate(logDir, DateTime.now().subtract(const Duration(days: 10)));
    _deleteOldLogs(oldLogFiles);
  }

  /// Performs periodic cleanup and forces log rotation to a new file
  Future<void> _performPeriodicCleanup() async {
    try {
      // First, clean up old log files
      final logDir = await getApplicationDocumentsDirectory();
      final oldLogFiles = await getLogsByDate(logDir, DateTime.now().subtract(const Duration(days: 10)));
      _deleteOldLogs(oldLogFiles);

      print('$statementPrefix Periodic cleanup and log rotation completed');
    } catch (e) {
      print('$statementPrefix Error during periodic cleanup: $e');
    }
  }

  /// Gets log files older than the specified date using file modified date
  /// This approach works regardless of filename format and supports long-running apps
  Future<List<File>> getLogsByDate(Directory logDir, DateTime date) async {
    final List<File> logFiles = [];
    // Match both old format (daily) and new format (daily with hour)
    final regex = RegExp(r'(SIP|APP)_\d{4}_\d{2}_\d{2}(_\d{2})?');
    if (await logDir.exists()) {
      for (var file in logDir.listSync().whereType<File>()) {
        final fileName = path.basename(file.path);
        final match = regex.firstMatch(fileName);
        if (match != null) {
          try {
            // Use file's last modified date instead of parsing filename
            final stat = await file.stat();
            final fileModifiedDate = stat.modified;

            // Check if file was last modified before the cutoff date
            if (fileModifiedDate.isBefore(date)) {
              logFiles.add(file);
            }
          } catch (e) {
            print('Error getting file stats for: $fileName - $e');
          }
        }
      }
    }
    return logFiles;
  }

  void _deleteOldLogs(List<File> logFiles) {
    for (var file in logFiles) {
      try {
        file.deleteSync();
        print('MyLogPrinter Deleted Old Log: ${file.path}');
      } catch (e) {
        print('MyLogPrinter Deleted Old Log: ${e.toString()} ${file.path}');
      }
    }
  }

  // Public method for testing purposes
  void deleteOldLogsForTesting(List<File> logFiles) {
    _deleteOldLogs(logFiles);
  }
}

class AnsiColor {
  AnsiColor.none()
      : fg = null,
        bg = null,
        color = false;

  AnsiColor.fg(this.fg)
      : bg = null,
        color = true;

  AnsiColor.bg(this.bg)
      : fg = null,
        color = true;

  /// ANSI Control Sequence Introducer, signals the terminal for settings.
  static const String ansiEsc = '\x1B[';

  /// Reset all colors and options for current SGRs to terminal defaults.
  static const String ansiDefault = '${ansiEsc}0m';

  final int? fg;
  final int? bg;
  final bool color;

  @override
  String toString() {
    if (fg != null) {
      return '${ansiEsc}38;5;${fg}m';
    } else if (bg != null) {
      return '${ansiEsc}48;5;${bg}m';
    } else {
      return '';
    }
  }

  String call(String msg) {
    if (color) {
      return '$msg$ansiDefault';
    } else {
      return msg;
    }
  }

  AnsiColor toFg() => AnsiColor.fg(bg);

  AnsiColor toBg() => AnsiColor.bg(fg);

  /// Defaults the terminal's foreground color without altering the background.
  String get resetForeground => color ? '${ansiEsc}39m' : '';

  /// Defaults the terminal's background color
}
