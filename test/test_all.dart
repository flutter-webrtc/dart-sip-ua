import 'test_classes.dart' as Classes;
import 'test_normalize_target.dart' as NormalizeTarget;
import 'test_parser.dart' as Parser;
import 'test_digest_authentication.dart' as DigestAuthentication;
import 'test_websocket.dart' as Websocket;

void main() {
  Classes.testFunctions.forEach((func) => func());
  Parser.testFunctions.forEach((func) => func());
  NormalizeTarget.testFunctions.forEach((func) => func());
  DigestAuthentication.testFunctions.forEach((func) => func());
  Websocket.testFunctions.forEach((func) => func());
}
