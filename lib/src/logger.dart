import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

import 'enum_helper.dart';
import 'stack_trace_nj.dart';

Logger logger = Log();

class Log extends Logger {
  Log() : super(printer: MyLogPrinter('.')) {
    StackTraceNJ frames = StackTraceNJ();

    if (frames.frames != null) {
      for (Stackframe frame in frames.frames!) {
        _localPath = frame.sourceFile.path
            .substring(frame.sourceFile.path.lastIndexOf('/'));
        break;
      }
    }
  }

  static late String _localPath;
  static Level _loggingLevel = Level.debug;
  static set loggingLevel(Level loggingLevel) => _loggingLevel = loggingLevel;
}

class MyLogPrinter extends LogPrinter {
  MyLogPrinter(this.currentWorkingDirectory);

  static final Map<Level, AnsiColor> levelColors = <Level, AnsiColor>{
    Level.verbose: AnsiColor.fg(AnsiColor.grey(0.5)),
    Level.debug: AnsiColor.none(),
    Level.info: AnsiColor.fg(12),
    Level.warning: AnsiColor.fg(208),
    Level.error: AnsiColor.fg(196),
  };

  bool colors = true;

  String currentWorkingDirectory;

  @override
  List<String> log(LogEvent event) {
    if (EnumHelper.getIndexOf(Level.values, Log._loggingLevel) >
        EnumHelper.getIndexOf(Level.values, event.level)) {
      // don't log events where the log level is set higher
      return <String>[];
    }
    DateFormat formatter = DateFormat('yyyy-MM-dd HH:mm:ss.');
    DateTime now = DateTime.now();
    String formattedDate = formatter.format(now) + now.millisecond.toString();

    AnsiColor color = _getLevelColor(event.level);

    StackTraceNJ frames = StackTraceNJ();
    int i = 0;
    int depth = 0;
    if (frames.frames != null) {
      for (Stackframe frame in frames.frames!) {
        i++;
        String path2 = frame.sourceFile.path;
        if (!path2.contains(Log._localPath) && !path2.contains('logger.dart')) {
          depth = i - 1;
          break;
        }
      }
    }

    print(color(
        '[$formattedDate] ${event.level} ${StackTraceNJ(skipFrames: depth).formatStackTrace(methodCount: 1)} ::: ${event.message}'));
    if (event.error != null) {
      print('${event.error}');
    }

    if (event.stackTrace != null) {
      if (event.stackTrace.runtimeType == StackTraceNJ) {
        StackTraceNJ st = event.stackTrace as StackTraceNJ;
        print(color('$st'));
      } else {
        print(color('${event.stackTrace}'));
      }
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
      return '$this$msg$ansiDefault';
    } else {
      return msg;
    }
  }

  AnsiColor toFg() => AnsiColor.fg(bg);

  AnsiColor toBg() => AnsiColor.bg(fg);

  /// Defaults the terminal's foreground color without altering the background.
  String get resetForeground => color ? '${ansiEsc}39m' : '';

  /// Defaults the terminal's background color without altering the foreground.
  String get resetBackground => color ? '${ansiEsc}49m' : '';

  static int grey(double level) => 232 + (level.clamp(0.0, 1.0) * 23).round();
}
