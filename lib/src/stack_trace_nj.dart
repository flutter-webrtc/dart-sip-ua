import 'dart:core' as core show StackTrace;
import 'dart:core';
import 'dart:io';

import 'package:path/path.dart';

class StackTraceNJ implements core.StackTrace {
  /// You can suppress call frames from showing
  /// by specifing a non-zero value for [skipFrames]
  /// If the workingDirectory is provided we will output
  /// a full file path to the dart library.
  StackTraceNJ({int skipFrames = 0, this.workingDirectory})
      : stackTrace = core.StackTrace.current,
        _skipFrames = skipFrames + 1; // always skip ourselves.

  static final RegExp stackTraceRegex =
      RegExp(r'#[0-9]+[\s]+(.+) \(([^\s]+)\)');
  final core.StackTrace stackTrace;

  final String? workingDirectory;
  final int _skipFrames;

  List<Stackframe>? _frames;

  ///
  /// Returns a File instance for the current stackframe
  ///
  File get sourceFile {
    return frames![0].sourceFile;
  }

  ///
  /// Returns the Filename for the current stackframe
  ///
  String get sourceFilename => basename(sourcePath);

  ///
  /// returns the full path for the current stackframe file
  ///
  String get sourcePath => sourceFile.path;

  ///
  /// Returns the filename for the current stackframe
  ///
  int get lineNo {
    return frames![0].lineNo;
  }

  /// Outputs a formatted string of the current stack_trace_nj
  /// showing upto [methodCount] methods in the trace.
  /// [methodCount] defaults to 10.

  String? formatStackTrace({bool showPath = false, int methodCount = 10}) {
    List<String> formatted = <String>[];
    int count = 0;

    for (Stackframe stackFrame in frames!) {
      // if (stackFrame.sourceFile.contains('log.dart') ||
      //     stackFrame.sourceFile.contains('package:logger')) {
      //   continue;
      // }

      String sourceFile;
      if (showPath) {
        sourceFile = stackFrame.sourceFile.path;
      } else {
        sourceFile = basename(stackFrame.sourceFile.path);
      }
      String newLine = '$sourceFile:${stackFrame.lineNo}';

      if (workingDirectory != null) {
        formatted.add('file:///${workingDirectory!}$newLine');
      } else {
        formatted.add(newLine);
      }
      if (++count == methodCount) {
        break;
      }
    }

    if (formatted.isEmpty) {
      return null;
    } else {
      return formatted.join('\n');
    }
  }

  List<Stackframe>? get frames {
    _frames ??= _extractFrames();
    return _frames;
  }

  @override
  String toString() {
    return formatStackTrace()!;
  }

  List<Stackframe> _extractFrames() {
    List<String> lines = stackTrace.toString().split('\n');

    // we don't want the call to StackTrace to be on the stack.
    int skipFrames = _skipFrames;

    List<Stackframe> stackFrames = <Stackframe>[];
    for (String line in lines) {
      if (skipFrames > 0) {
        skipFrames--;
        continue;
      }
      Match? match = stackTraceRegex.matchAsPrefix(line);
      if (match == null) continue;

      // source is one of two formats
      // file:///.../squarephone_app/filename.dart:column:line
      // package:/squarephone/.path./filename.dart:column:line
      String source = match.group(2)!;
      List<String> sourceParts = source.split(':');
      ArgumentError.value(sourceParts.length == 4,
          "Stackframe source does not contain the expeted no of colons '$source'");

      String column = '0';
      String lineNo = '0';
      String sourcePath = sourceParts[1];
      if (sourceParts.length > 2) {
        lineNo = sourceParts[2];
      }
      if (sourceParts.length > 3) {
        column = sourceParts[3];
      }

      // the actual contents of the line (sort of)
      String? details = match.group(1);

      sourcePath = sourcePath.replaceAll('<anonymous closure>', '()');
      sourcePath = sourcePath.replaceAll('package:', '');
      sourcePath = sourcePath.replaceFirst('squarephone', '/lib');

      Stackframe frame = Stackframe(
          File(sourcePath), int.parse(lineNo), int.parse(column), details);
      stackFrames.add(frame);
    }
    return stackFrames;
  }
}

///
/// A single frame from a stack trace.
/// Holds the sourceFile name and line no.
///
class Stackframe {
  Stackframe(this.sourceFile, this.lineNo, this.column, this.details);
  final File sourceFile;
  final int lineNo;
  final int column;
  final String? details;
}
