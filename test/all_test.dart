import 'test_classes.dart' as Classes;
import 'test_digest_authentication.dart' as DigestAuthentication;
import 'test_normalize_target.dart' as NormalizeTarget;
import 'test_parser.dart' as Parser;
import 'test_websocket.dart' as Websocket;

void main() {
  for (Function func in Classes.testFunctions) {
    func();
  }
  for (Function func in Parser.testFunctions) {
    func();
  }
  for (Function func in NormalizeTarget.testFunctions) {
    func();
  }
  for (Function func in DigestAuthentication.testFunctions) {
    func();
  }
  //for (Function _func in Websocket.testFunctions) {
  //func();
  //}
}
