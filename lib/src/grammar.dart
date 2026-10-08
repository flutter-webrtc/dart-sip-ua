import 'grammar_parser.dart';

class Grammar {
  static dynamic parse(String input, String startRule) {
    GrammarParser parser = GrammarParser('');
    dynamic result = parser.parse(input, startRule);
    if (!parser.success) {
      // Not printed: release builds would put the SIP header in the system log.
      throw FormatException('Cannot parse "$startRule"');
    }
    return result;
  }
}
