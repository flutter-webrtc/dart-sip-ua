import 'test_classes.dart' as Classes;
import 'test_digest_authentication.dart' as DigestAuthentication;
import 'test_normalize_target.dart' as NormalizeTarget;
import 'test_parser.dart' as Parser;
import 'test_websocket.dart' as Websocket;

void main() {
  Classes.testFunctions.forEach((Function func) => func());
  Parser.testFunctions.forEach((Function func) => func());
  NormalizeTarget.testFunctions.forEach((Function func) => func());
  DigestAuthentication.testFunctions.forEach((Function func) => func());
  Websocket.testFunctions.forEach((Function func) => func());
}
