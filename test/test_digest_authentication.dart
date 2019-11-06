import 'package:test/test.dart';
import 'package:sip_ua/src/digest_authentication.dart';

import 'package:sip_ua/src/constants.dart';

// Results of this tests originally obtained from RFC 2617 and:
// 'https://pernau.at/kd/sipdigest.php'

var testFunctions = [
  () =>
      test("DigestAuthentication: parse no auth testrealm@host.com -RFC 2617-",
          () {
        SipMethod method = SipMethod.GET;
        var ruri = '/dir/index.html';
        var cnonce = '0a4f113b';
        var credentials = Credentials.fromMap({
          'username': 'Mufasa',
          'password': 'Circle Of Life',
          'realm': 'testrealm@host.com',
          'ha1': null
        });
        var challenge = Challenge.fromMap({
          'algorithm': 'MD5',
          'realm': 'testrealm@host.com',
          'nonce': 'dcd98b7102dd2f0e8b11d0f600bfb0c093',
          'opaque': '5ccc069c403ebaf9f0171e9517f40e41',
          'stale': null,
          'qop': 'auth'
        });

        var digest = new DigestAuthentication(credentials);

        digest.authenticate(method, challenge, ruri, cnonce);

        expect(digest.response, '6629fae49393a05397450978507c4ef1');
      }),
  () => test('DigestAuthentication: digest authenticate qop = null', () {
        SipMethod method = SipMethod.REGISTER;
        var ruri = 'sip:testrealm@host.com';
        var credentials = Credentials.fromMap({
          'username': 'testuser',
          'password': 'testpassword',
          'realm': 'testrealm@host.com',
          'ha1': null
        });
        var challenge = Challenge.fromMap({
          'algorithm': 'MD5',
          'realm': 'testrealm@host.com',
          'nonce': '5a071f75353f667787615249c62dcc7b15a4828f',
          'opaque': null,
          'stale': null,
          'qop': null
        });

        var digest = new DigestAuthentication(credentials);

        digest.authenticate(method, challenge, ruri);

        expect(digest.response, 'f99e05f591f147facbc94ff23b4b1dee');
      }),
  () => test('DigestAuthentication: digest authenticate qop = auth', () {
        SipMethod method = SipMethod.REGISTER;
        var ruri = 'sip:testrealm@host.com';
        var cnonce = '0a4f113b';
        var credentials = Credentials.fromMap({
          'username': 'testuser',
          'password': 'testpassword',
          'realm': 'testrealm@host.com',
          'ha1': null
        });
        var challenge = Challenge.fromMap({
          'algorithm': 'MD5',
          'realm': 'testrealm@host.com',
          'nonce': '5a071f75353f667787615249c62dcc7b15a4828f',
          'opaque': null,
          'stale': null,
          'qop': 'auth'
        });

        var digest = new DigestAuthentication(credentials);

        digest.authenticate(method, challenge, ruri, cnonce);

        expect(digest.response, 'a69b9c2ea0dea1437a21df6ddc9b05e4');
      }),
  () => test(
          'DigestAuthentication: digest authenticate qop = auth-int and empty body',
          () {
        SipMethod method = SipMethod.REGISTER;
        var ruri = 'sip:testrealm@host.com';
        var cnonce = '0a4f113b';
        var credentials = Credentials.fromMap({
          'username': 'testuser',
          'password': 'testpassword',
          'realm': 'testrealm@host.com',
          'ha1': null
        });
        var challenge = Challenge.fromMap({
          'algorithm': 'MD5',
          'realm': 'testrealm@host.com',
          'nonce': '5a071f75353f667787615249c62dcc7b15a4828f',
          'opaque': null,
          'stale': null,
          'qop': 'auth-int'
        });

        var digest = new DigestAuthentication(credentials);

        digest.authenticate(method, challenge, ruri, cnonce);

        expect(digest.response, '82b3cab8b1c4df404434db6a0581650c');
      }),
  () => test(
          'DigestAuthentication: digest authenticate qop = auth-int and non-empty body',
          () {
        SipMethod method = SipMethod.REGISTER;
        var ruri = 'sip:testrealm@host.com';
        var body = 'TEST BODY';
        var cnonce = '0a4f113b';
        var credentials = Credentials.fromMap({
          'username': 'testuser',
          'password': 'testpassword',
          'realm': 'testrealm@host.com',
          'ha1': null
        });
        var challenge = Challenge.fromMap({
          'algorithm': 'MD5',
          'realm': 'testrealm@host.com',
          'nonce': '5a071f75353f667787615249c62dcc7b15a4828f',
          'opaque': null,
          'stale': null,
          'qop': 'auth-int'
        });

        var digest = new DigestAuthentication(credentials);

        digest.authenticate(method, challenge, ruri, cnonce, body);

        expect(digest.response, '7bf0e9de3fbb5da121974509d617f532');
      })
];

void main() {
  testFunctions.forEach((func) => func());
}
