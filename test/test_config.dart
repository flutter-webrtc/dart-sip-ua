import 'package:test/test.dart';

import 'package:sip_ua/src/config.dart' as config;
import 'package:sip_ua/src/utils.dart' as Utils;

List<void Function()> testFunctions = <void Function()>[
  () => test('Config: contact_uri given as URI is copied to settings', () {
        // SIPUAHelper.start() converts UaSettings.contact_uri (String) into
        // a URI via Utils.normalizeTarget before config.load runs, so the
        // checker must accept URI instances.
        config.Settings src = config.Settings()
          ..contact_uri = Utils.normalizeTarget('sip:alice@example.com');
        config.Settings dst = config.Settings();

        config.checks.optional['contact_uri']!(src, dst);

        expect(dst.contact_uri, isNotNull);
        expect(dst.contact_uri!.user, 'alice');
        expect(dst.contact_uri!.host, 'example.com');
      }),
  () => test('Config: null contact_uri stays null', () {
        config.Settings src = config.Settings()..contact_uri = null;
        config.Settings dst = config.Settings();

        config.checks.optional['contact_uri']!(src, dst);

        expect(dst.contact_uri, isNull);
      })
];

void main() {
  for (Function func in testFunctions) {
    func();
  }
}
