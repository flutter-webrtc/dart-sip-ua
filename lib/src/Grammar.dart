import 'package:sip_ua/src/grammar_parser.dart';

class Grammar {
  static parse(input, startRule){
    var parser = new GrammarParser('');
    return parser.parse(input, startRule);
  }
}