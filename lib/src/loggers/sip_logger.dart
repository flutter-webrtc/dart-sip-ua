import 'dart:core';

import '../core/env/config.dart';
import '../loggers/log_level.dart';

import '../loggers/log_printer.dart';
// ignore_for_file: avoid_print

class Log {
  Log();

  void dHeader(
    dynamic message, {
    dynamic options,
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    String out = message as String;
    if (!out.contains("sip_logger.dart")) {
      List<String> lines = message.toString().split('\r\n');
      for (final line in lines) {
        logger.log(Level.trace, " $line", options: options);
      }
    }
  }

  static String removeLastCrLf(String input) {
    try {
      final RegExp regex = RegExp(r'(?:(?!\r\n)[\s\S])*(?:\r\n)(?![\s\S]*\r\n)');
      return input.replaceAllMapped(regex, (match) => match.group(0)!.replaceAll("\r\n", ""));
    } catch (e) {
      return input;
    }
  }

  static void printWrapped(String text) {
    final pattern = RegExp('.{1,800}'); // 800 is the size of each chunk
    pattern.allMatches(text).forEach((match) => print(match.group(0)));
  }

  void d(
    dynamic message, {
    dynamic options,
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    String out = message as String;
    if (!out.contains("sip_logger.dart")) {
      logger.log(Level.trace, out, options: options);
    }
  }

  void e(
    dynamic message, {
    dynamic options,
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) {
    String out = message as String;
    if (!out.contains("sip_logger.dart")) {
      logger.log(
        Level.error,
        out.replaceAll("\r\n", "\n"),
      );
    }
  }

  void log(
    Level level,
    dynamic message, {
    dynamic options,
    DateTime? time,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    DateTime now = DateTime.now();
    try {
      AnsiColor color = level.value == 5000 ? AnsiColor.fg(31) : AnsiColor.fg(34);
      bool useColor = EnvConfig.USE_ANSI_COLOR_IN_LOGS;
      printWrapped("${useColor ? color : ''} SIP_LOG $now $message");
      if (EnvConfig.LOGGING_ENABLED) {
        await logPrinter.write(" $now, $message");
      }
    } catch (e) {
      print("SIP_LOG error ${e.toString()}");
    }
  }
}

MyLogPrinter logPrinter = MyLogPrinter(filePrefix: 'SIP');
Log logger = Log();
