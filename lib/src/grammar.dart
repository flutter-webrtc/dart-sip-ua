import "package:parser_error/parser_error.dart";

import 'grammar_parser.dart';

class Grammar {
  static parse(String input, String startRule) {
    var parser = GrammarParser('');
    var result = parser.parse(input, startRule);
    if (!parser.success) {
      List<ParserErrorMessage> messages = [];
      for (var error in parser.errors()) {
        messages.add(
            ParserErrorMessage(error.message, error.start, error.position));
      }

      var strings = ParserErrorFormatter.format(parser.text, messages);
      print(strings.join("\n"));
      throw FormatException();
    }
    return result;
  }
}
