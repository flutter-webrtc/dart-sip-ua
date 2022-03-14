import 'package:sip_ua/src/uri.dart';
import 'package:sip_ua/src/utils.dart' as Utils;
import 'package:test/test.dart';

List<void Function()> testFunctions = <void Function()>[
  () => test('NormalizeTarget: valid targets', () {
        String domain = 'jssip.net';

        void test_ok(dynamic given_data, dynamic expected) {
          URI? uri = Utils.normalizeTarget(given_data, domain);
          expect(uri.toString(), expected);
        }

        test_ok('%61lice', 'sip:alice@jssip.net');
        test_ok('ALICE', 'sip:ALICE@jssip.net');
        test_ok('alice@DOMAIN.com', 'sip:alice@domain.com');
        test_ok('iñaki', 'sip:i%C3%B1aki@jssip.net');
        test_ok('€€€', 'sip:%E2%82%AC%E2%82%AC%E2%82%AC@jssip.net');
        test_ok('iñaki@aliax.net', 'sip:i%C3%B1aki@aliax.net');
        test_ok('SIP:iñaki@aliax.net:7070', 'sip:i%C3%B1aki@aliax.net:7070');
        test_ok('SIPs:iñaki@aliax.net:7070', 'sip:i%C3%B1aki@aliax.net:7070');
        test_ok('ibc@gmail.com@aliax.net', 'sip:ibc%40gmail.com@aliax.net');
        test_ok('alice-1:passwd', 'sip:alice-1@jssip.net');
        test_ok('SIP:alice-2:passwd', 'sip:alice-2@jssip.net');
        test_ok('sips:alice-2:passwd', 'sip:alice-2@jssip.net');
        test_ok('alice-3:passwd@domain.COM', 'sip:alice-3@domain.com');
        test_ok('SIP:alice-4:passwd@domain.COM', 'sip:alice-4@domain.com');
        test_ok('sip:+1234@aliax.net', 'sip:+1234@aliax.net');
        test_ok('+999', 'sip:+999@jssip.net');
        test_ok('*999', 'sip:*999@jssip.net');
        test_ok('#999/?:1234', 'sip:%23999/?@jssip.net');
        test_ok('tel:+12345678', 'sip:+12345678@jssip.net');
        test_ok('tel:(+34)-944-43-89', 'sip:+349444389@jssip.net');
        test_ok('+123.456.78-9', 'sip:+123456789@jssip.net');
        test_ok('+ALICE-123.456.78-9', 'sip:+ALICE-123.456.78-9@jssip.net');
      }),
  () => test('NormalizeTarget: invalid targets', () {
        String domain = 'jssip.net';

        void test_error(dynamic given_data) {
          expect(Utils.normalizeTarget(given_data, domain), null);
        }

        test_error(null);
        test_error(false);
        test_error(true);
        test_error('');

        //test_error('ibc@iñaki.com');
        //test_error('ibc@aliax.net;;;;;');

        expect(Utils.normalizeTarget('alice'), null);
      })
];

void main() {
  for (Function func in testFunctions) {
    func();
  }
}
