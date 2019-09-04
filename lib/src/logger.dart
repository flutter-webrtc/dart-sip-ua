enum Level { verbose, debug, info, warning, error, failure }

class Logger {
  String _tag;
  bool colors;
  bool printTime;
  static final levelColors = {
    Level.verbose: AnsiColor.fg(AnsiColor.grey(0.5)),
    Level.debug: AnsiColor.none(),
    Level.info: AnsiColor.fg(12),
    Level.warning: AnsiColor.fg(208),
    Level.error: AnsiColor.fg(196),
    Level.failure: AnsiColor.fg(199),
  };
  static DateTime _startTime;

  Logger(tag) {
    this._tag = 'DartSIP:' + tag;
    this.colors = false;
    this.printTime = true;
    if (_startTime == null) {
      _startTime = DateTime.now();
    }
  }

  void error(error) {
    this.log('[' + _tag + '] ERROR: ' + error, Level.error);
  }

  void verbose(msg) {
    this.log('[' + _tag + '] VERBOSE: ' + msg, Level.verbose);
  }

  void info(msg) {
    this.log('[' + _tag + '] INFO: ' + msg, Level.info);
  }

  void debug(msg) {
    this.log('[' + _tag + '] DEBUG: ' + msg, Level.debug);
  }

  void warn(msg) {
    this.log('[' + _tag + '] WARN: ' + msg, Level.warning);
  }

  void failure(error) {
    var log = '[' + _tag + '] FAILURE: ' + error;
    this.log(log, Level.failure);
    throw (log);
  }

  void log(message, level) {
    String timeStr = printTime? getTime() : '';
    formatAndPrint(level, message, timeStr);
  }

  formatAndPrint(Level level, String message, String time) {
    var color = _getLevelColor(level);
    for (var line in message.split('\n')) {
      print(color('$time $line'));
    }
  }

  AnsiColor _getLevelColor(Level level) {
    if (colors) {
      return levelColors[level];
    } else {
      return AnsiColor.none();
    }
  }

  String getTime() {
    String _threeDigits(int n) {
      if (n >= 100) return "${n}";
      if (n >= 10) return "0${n}";
      return "00${n}";
    }

    String _twoDigits(int n) {
      if (n >= 10) return "${n}";
      return "0${n}";
    }

    var now = DateTime.now();
    String h = _twoDigits(now.hour);
    String min = _twoDigits(now.minute);
    String sec = _twoDigits(now.second);
    String ms = _threeDigits(now.millisecond);
    var timeSinceStart = now.difference(_startTime).toString();
    return "$h:$min:$sec.$ms (+$timeSinceStart)";
  }
}

class AnsiColor {
  /// ANSI Control Sequence Introducer, signals the terminal for new settings.
  static const ansiEsc = '\x1B[';

  /// Reset all colors and options for current SGRs to terminal defaults.
  static const ansiDefault = "${ansiEsc}0m";

  final int fg;
  final int bg;
  final bool color;

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

  String toString() {
    if (fg != null) {
      return "${ansiEsc}38;5;${fg}m";
    } else if (bg != null) {
      return "${ansiEsc}48;5;${bg}m";
    } else {
      return "";
    }
  }

  String call(String msg) {
    if (color) {
      return "${this}$msg$ansiDefault";
    } else {
      return msg;
    }
  }

  AnsiColor toFg() => AnsiColor.fg(bg);

  AnsiColor toBg() => AnsiColor.bg(fg);

  /// Defaults the terminal's foreground color without altering the background.
  String get resetForeground => color ? "${ansiEsc}39m" : "";

  /// Defaults the terminal's background color without altering the foreground.
  String get resetBackground => color ? "${ansiEsc}49m" : "";

  static int grey(double level) => 232 + (level.clamp(0.0, 1.0) * 23).round();
}
