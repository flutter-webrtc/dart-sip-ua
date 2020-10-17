import 'package:parser_error/parser_error.dart';

import 'grammar_parser.dart';

class Grammar {
  static dynamic parse(String input, String startRule) {
    GrammarParser parser = GrammarParser('');
    dynamic result = parser.parse(input, startRule);
    if (!parser.success) {
      result = parser.parse(input, startRule);
      List<ParserErrorMessage> messages = <ParserErrorMessage>[];
      for (GrammarParserError error in parser.errors()) {
        messages.add(
            ParserErrorMessage(error.message, error.start, error.position));
      }

      List<String> strings = ParserErrorFormatter.format(parser.text, messages);
      print('input => $input, rule => $startRule');
      print(strings.join('\n'));
      throw FormatException();
    }
    return result;
  }
}
