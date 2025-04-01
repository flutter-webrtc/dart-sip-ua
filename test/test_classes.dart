import 'package:test/test.dart';

import 'package:sip_ua/src/name_addr_header.dart';
import 'package:sip_ua/src/uri.dart';

List<void Function()> testFunctions = <void Function()>[
  () => test('Class: URI', () {
        URI uri = URI(null, 'alice', 'jssip.net', 6060);

        expect(uri.scheme, 'sip');
        expect(uri.user, 'alice');
        expect(uri.host, 'jssip.net');
        expect(uri.port, 6060);
        expect(uri.toString(), 'sip:alice@jssip.net:6060');
        expect(uri.toAor(), 'sip:alice@jssip.net');
        expect(uri.toAor(show_port: false), 'sip:alice@jssip.net');
        expect(uri.toAor(show_port: true), 'sip:alice@jssip.net:6060');

        uri.scheme = 'SIPS';
        expect(uri.scheme, 'sips');
        expect(uri.toAor(), 'sips:alice@jssip.net');
        uri.scheme = 'sip';

        uri.user = 'Iñaki ðđ';
        expect(uri.user, 'Iñaki ðđ');
        expect(uri.toString(), 'sip:I%C3%B1aki%20%C3%B0%C4%91@jssip.net:6060');
        expect(uri.toAor(), 'sip:I%C3%B1aki%20%C3%B0%C4%91@jssip.net');

        uri.user = '%61lice';
        expect(uri.toAor(), 'sip:alice@jssip.net');

        uri.user = null;
        expect(uri.user, null);
        expect(uri.toAor(), 'sip:jssip.net');
        uri.user = 'alice';

        // causes compile error with strict
        // expect(() => uri.host = {'bar': 'foo'}, throwsNoSuchMethodError);

        expect(uri.host, 'jssip.net');

        uri.host = 'VERSATICA.com';
        expect(uri.host, 'versatica.com');
        uri.host = 'jssip.net';

        uri.port = null;
        expect(uri.port, null);

        uri.port = null;
        expect(uri.port, null);

        // causes compile error with strict
        //uri.port = 'ABCD'; // Should become null.
        //expect(uri.toString(), 'sip:alice@jssip.net');

        // causes compile error with strict
        //uri.port = '123'; // Should become 123.
        //expect(uri.toString(), 'sip:alice@jssip.net:123');

        uri.port = 0;
        expect(uri.port, 0);
        expect(uri.toString(), 'sip:alice@jssip.net:0');
        uri.port = null;

        expect(uri.hasParam('foo'), false);

        uri.setParam('Foo', null);
        expect(uri.hasParam('FOO'), true);

        uri.setParam('Baz', 123);
        expect(uri.getParam('baz'), '123');
        expect(uri.toString(), 'sip:alice@jssip.net;foo;baz=123');

        uri.setParam('zero', 0);
        expect(uri.hasParam('ZERO'), true);
        expect(uri.getParam('ZERO'), '0');
        expect(uri.toString(), 'sip:alice@jssip.net;foo;baz=123;zero=0');
        expect(uri.deleteParam('ZERO'), '0');

        expect(uri.deleteParam('baZ'), '123');
        expect(uri.deleteParam('NOO'), null);
        expect(uri.toString(), 'sip:alice@jssip.net;foo');

        uri.clearParams();
        expect(uri.toString(), 'sip:alice@jssip.net');

        expect(uri.hasHeader('foo'), false);

        uri.setHeader('Foo', 'LALALA');
        expect(uri.hasHeader('FOO'), true);
        expect(uri.getHeader('FOO'), <String>['LALALA']);
        expect(uri.toString(), 'sip:alice@jssip.net?Foo=LALALA');

        uri.setHeader('bAz', <String>['ABC-1', 'ABC-2']);
        expect(uri.getHeader('baz'), <String>['ABC-1', 'ABC-2']);
        expect(uri.toString(),
            'sip:alice@jssip.net?Foo=LALALA&Baz=ABC-1&Baz=ABC-2');

        expect(uri.deleteHeader('baZ'), <String>['ABC-1', 'ABC-2']);
        expect(uri.deleteHeader('NOO'), null);

        uri.clearHeaders();
        expect(uri.toString(), 'sip:alice@jssip.net');

        URI uri2 = uri.clone();

        expect(uri2.toString(), uri.toString());
        uri2.user = 'popo';
        expect(uri2.user, 'popo');
        expect(uri.user, 'alice');
      }),
  () => test('Class: NameAddr', () {
        URI uri = URI('sip', 'alice', 'jssip.net');
        NameAddrHeader name = NameAddrHeader(uri, 'Alice æßð');

        expect(name.display_name, 'Alice æßð');
        expect(name.toString(), '"Alice æßð" <sip:alice@jssip.net>');

        name.display_name = null;
        expect(name.toString(), '<sip:alice@jssip.net>');

        name.display_name = 0;
        expect(name.toString(), '"0" <sip:alice@jssip.net>');

        name.display_name = '';
        expect(name.toString(), '<sip:alice@jssip.net>');

        name.setParam('Foo', null);
        expect(name.hasParam('FOO'), true);

        name.setParam('Baz', 123);
        expect(name.getParam('baz'), '123');
        expect(name.toString(), '<sip:alice@jssip.net>;foo;baz=123');

        expect(name.deleteParam('bAz'), '123');

        name.clearParams();
        expect(name.toString(), '<sip:alice@jssip.net>');

        NameAddrHeader name2 = name.clone();

        expect(name2.toString(), name.toString());
        name2.display_name = '@ł€';
        expect(name2.display_name, '@ł€');
      })
];

void main() {
  for (Function func in testFunctions) {
    func();
  }
}
