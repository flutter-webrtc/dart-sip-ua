import 'package:sip_ua/src/grammar_parser.dart';
import "package:parser_error/parser_error.dart";

class Grammar {
  static parse(input, startRule) {
    var parser = new GrammarParser('');
    var result = parser.parse(input, startRule);
    if (!parser.success) {
      List<ParserErrorMessage> messages = [];
      for (var error in parser.errors()) {
        messages.add(
            new ParserErrorMessage(error.message, error.start, error.position));
      }

      var strings = ParserErrorFormatter.format(parser.text, messages);
      print(strings.join("\n"));
      throw new FormatException();
    }
    return result;
  }
}
