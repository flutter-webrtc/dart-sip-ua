import 'package:test/test.dart';

import 'package:sip_ua/src/data.dart';
import 'package:sip_ua/src/grammar.dart';
import 'package:sip_ua/src/name_addr_header.dart';
import 'package:sip_ua/src/uri.dart';

List<void Function()> testFunctions = <void Function()>[
  () => test('Parser: Host => [ domain, ipv4, ipv6 ].', () {
        dynamic data = Grammar.parse('www.google.com', 'host');
        expect(data['host_type'], 'domain');

        data = Grammar.parse('www.163.com', 'host');
        expect(data['host_type'], 'domain');

        data = Grammar.parse('myhost123', 'host');
        expect(data['host_type'], 'domain');

        data = Grammar.parse('localhost', 'host');
        expect(data['host_type'], 'domain');

        data = Grammar.parse('1.2.3.4.bar.qwe-asd.foo', 'host');
        expect(data['host_type'], 'domain');

        data = Grammar.parse('192.168.0.1', 'host');
        expect(data['host_type'], 'IPv4');

        data = Grammar.parse('127.0.0.1', 'host');
        expect(data['host_type'], 'IPv4');

        data = Grammar.parse('[::1]', 'host');
        expect(data['host_type'], 'IPv6');

        data = Grammar.parse('[1:0:fF::432]', 'host');
        expect(data['host_type'], 'IPv6');
      }),
  () => test('Parser: URI.', () {
        String uriData =
            'siP:%61liCE@versaTICA.Com:6060;TRansport=TCp;Foo=ABc;baz?X-Header-1=AaA1&X-Header-2=BbB&x-header-1=AAA2';
        URI uri = URI.parse(uriData);
        print('uriData => $uriData');
        print('uri => $uri');
        expect(uri.scheme, 'sip');
        expect(uri.user, 'aliCE');
        expect(uri.port, 6060);
        expect(uri.hasParam('transport'), true);
        expect(uri.hasParam('nooo'), false);
        expect(uri.getParam('transport'), 'tcp');

        expect(uri.getParam('foo'), 'ABc');
        expect(uri.getParam('baz'), null);
        expect(uri.getParam('nooo'), null);
        expect(uri.getHeader('x-header-1'), <String>['AaA1', 'AAA2']);
        expect(uri.getHeader('X-HEADER-2'), <String>['BbB']);
        expect(uri.getHeader('nooo'), null);
        print('uri => $uri');
        expect(uri.toString(),
            'sip:aliCE@versatica.com:6060;transport=tcp;foo=ABc;baz?X-Header-1=AaA1&X-Header-1=AAA2&X-Header-2=BbB');
        expect(uri.toAor(show_port: true), 'sip:aliCE@versatica.com:6060');

        // Alter data.
        uri.user = 'Iñaki:PASSWD';
        expect(uri.user, 'Iñaki:PASSWD');
        expect(uri.deleteParam('foo'), 'ABc');
        expect(uri.deleteHeader('x-header-1'), <String>['AaA1', 'AAA2']);
        uri.deleteHeader('x-header-1');
        expect(uri.toString(),
            'sip:I%C3%B1aki:PASSWD@versatica.com:6060;transport=tcp;baz?X-Header-2=BbB');
        expect(uri.toAor(), 'sip:I%C3%B1aki:PASSWD@versatica.com');
        uri.clearParams();
        uri.clearHeaders();
        uri.port = null;
        expect(uri.toString(), 'sip:I%C3%B1aki:PASSWD@versatica.com');
        expect(uri.toAor(), 'sip:I%C3%B1aki:PASSWD@versatica.com');
      }),
  () => test('Parser: NameAddr with token display_name.', () {
        String data =
            'Foo    Foo Bar\tBaz<SIP:%61liCE@versaTICA.Com:6060;TRansport=TCp;Foo=ABc;baz?X-Header-1=AaA1&X-Header-2=BbB&x-header-1=AAA2>;QWE=QWE;ASd';
        NameAddrHeader name = NameAddrHeader.parse(data);
        print('name => $name');

        expect(name.display_name, 'Foo Foo Bar Baz');
      }),
  () => test('Parser: NameAddr with no space between DQUOTE and LAQUOT.', () {
        String data =
            '"Foo"<SIP:%61liCE@versaTICA.Com:6060;TRansport=TCp;Foo=ABc;baz?X-Header-1=AaA1&X-Header-2=BbB&x-header-1=AAA2>;QWE=QWE;ASd';
        NameAddrHeader name = NameAddrHeader.parse(data);
        print('name => $name');

        expect(name.display_name, 'Foo');
      }),
  () => test('Parser: NameAddr with no space between DQUOTE and LAQUOT', () {
        String data =
            '<SIP:%61liCE@versaTICA.Com:6060;TRansport=TCp;Foo=ABc;baz?X-Header-1=AaA1&X-Header-2=BbB&x-header-1=AAA2>;QWE=QWE;ASd';
        NameAddrHeader name = NameAddrHeader.parse(data);
        print('name => $name');

        expect(name.display_name, null);
      }),
  () => test('Parser: NameAddr.', () {
        String data =
            '  "Iñaki ðđøþ foo \\"bar\\" \\\\\\\\ \\\\ \\\\d \\\\\\\\d \\\\\' \\\\\\"sdf\\\\\\""  '
            '<SIP:%61liCE@versaTICA.Com:6060;TRansport=TCp;Foo=ABc;baz?X-Header-1=AaA1&X-Header-2=BbB&x-header-1=AAA2>;QWE=QWE;ASd';
        NameAddrHeader name = NameAddrHeader.parse(data);
        print('name => $name');
        expect(name.display_name,
            'Iñaki ðđøþ foo \\"bar\\" \\\\\\\\ \\\\ \\\\d \\\\\\\\d \\\\\' \\\\\\"sdf\\\\\\"');
      }),
  () => test('Parser: multiple Contact.', () {
        String data =
            '"Iñaki @ł€" <SIP:+1234@ALIAX.net;Transport=WS>;+sip.Instance="abCD", sip:bob@biloxi.COM;headerParam, <sip:DOMAIN.com:5>';
        dynamic contacts = Grammar.parse(data, 'Contact');
        print('contacts => $contacts');

        expect(contacts.length, 3);
        dynamic c1 = contacts[0]['parsed'];
        dynamic c2 = contacts[1]['parsed'];
        dynamic c3 = contacts[2]['parsed'];

        // Parsed data.
        expect(c1.display_name, 'Iñaki @ł€');
        expect(c1.hasParam('+sip.instance'), true);
        expect(c1.hasParam('nooo'), false);
        expect(c1.getParam('+SIP.instance'), '"abCD"');
        expect(c1.getParam('nooo'), null);

        expect(c1.uri.scheme, 'sip');
        expect(c1.uri.user, '+1234');
        expect(c1.uri.host, 'aliax.net');
        expect(c1.uri.port, null);
        expect(c1.uri.getParam('transport'), 'ws');
        expect(c1.uri.getParam('foo'), null);
        expect(c1.uri.getHeader('X-Header'), null);
        expect(c1.toString(),
            '"Iñaki @ł€" <sip:+1234@aliax.net;transport=ws>;+sip.instance="abCD"');

        // Alter data.
        c1.display_name = '€€€';
        expect(c1.display_name, '€€€');
        c1.uri.user = '+999';
        expect(c1.uri.user, '+999');
        c1.setParam('+sip.instance', '"zxCV"');
        expect(c1.getParam('+SIP.instance'), '"zxCV"');
        c1.setParam('New-Param', null);
        expect(c1.hasParam('NEW-param'), true);
        c1.uri.setParam('New-Param', null);
        expect(c1.toString(),
            '"€€€" <sip:+999@aliax.net;transport=ws;new-param>;+sip.instance="zxCV";new-param');

        // Parsed data.
        expect(c2.display_name, null);
        expect(c2.hasParam('HEADERPARAM'), true);
        expect(c2.uri.scheme, 'sip');
        expect(c2.uri.user, 'bob');
        expect(c2.uri.host, 'biloxi.com');
        expect(c2.uri.port, null);
        expect(c2.uri.hasParam('headerParam'), false);
        expect(c2.toString(), '<sip:bob@biloxi.com>;headerparam');

        // Alter data.
        c2.display_name = '@ł€ĸłæß';
        expect(c2.toString(), '"@ł€ĸłæß" <sip:bob@biloxi.com>;headerparam');

        // Parsed data.
        expect(c3.display_name, null);
        expect(c3.uri.scheme, 'sip');
        expect(c3.uri.user, null);
        expect(c3.uri.host, 'domain.com');
        expect(c3.uri.port, 5);
        expect(c3.uri.hasParam('nooo'), false);
        expect(c3.toString(), '<sip:domain.com:5>');

        // Alter data.
        c3.uri.setParam('newUriParam', 'zxCV');
        c3.setParam('newHeaderParam', 'zxCV');
        expect(c3.toString(),
            '<sip:domain.com:5;newuriparam=zxCV>;newheaderparam=zxCV');

        data =
            '<sip:4f39zg8g@9c816wt8uay8.invalid>;+sip.ice;reg-id=1;+sip.instance="<urn:uuid:9f331588-736e-4b03-924a-2bb6e69446a7>";expires=600';
        contacts = Grammar.parse(data, 'Contact');
        dynamic c0 = contacts[0]['parsed'];
        expect(c0.uri.host, '9c816wt8uay8.invalid');
      }),
  () => test('Parser: Via.', () {
        String data =
            'SIP /  3.0 \r\n / UDP [1:ab::FF]:6060 ;\r\n  BRanch=1234;Param1=Foo;paRAM2;param3=Bar';
        dynamic via = Grammar.parse(data, 'Via');

        print('via => $via');

        expect(via.protocol, 'SIP');
        expect(via.transport, 'UDP');
        expect(via.host, '[1:ab::FF]');
        expect(via.host_type, 'IPv6');
        expect(via.port, 6060);
        expect(via.branch, '1234');
        expect(via.params, <String, dynamic>{
          'branch': '1234',
          'param1': 'Foo',
          'param2': null,
          'param3': 'Bar'
        });
      }),
  () => test('Parser: CSeq.', () {
        String data = '123456  CHICKEN';
        dynamic cseq = Grammar.parse(data, 'CSeq');

        print('cseq => $cseq');

        expect(cseq.cseq, 123456);
        expect(cseq.method_str, 'CHICKEN');
      }),
  () => test('Parser: authentication challenge.', () {
        String data =
            'Digest realm =  "[1:ABCD::abc]", nonce =  "31d0a89ed7781ce6877de5cb032bf114", qop="AUTH,autH-INt", algorithm =  md5  ,  stale =  TRUE , opaque = "00000188"';
        dynamic auth = Grammar.parse(data, 'challenge');

        print('auth => $auth');
        expect(auth.realm, '[1:ABCD::abc]');
        expect(auth.nonce, '31d0a89ed7781ce6877de5cb032bf114');
        expect(auth.qop[0], 'auth');
        expect(auth.qop[1], 'auth-int');
        expect(auth.algorithm, 'MD5');
        expect(auth.stale, true);
        expect(auth.opaque, '00000188');
      }),
  () => test('Parser: authentication challenge2.', () {
        String data =
            'Digest algorithm="MD5",qop="auth",realm="some.sip.domain.com",nonce="217384172034871293047102934",otherk1="other_v1"';
        dynamic auth = Grammar.parse(data, 'challenge');
        print('auth => $auth');
        expect(auth.realm, 'some.sip.domain.com');
        expect(auth.nonce, '217384172034871293047102934');
        expect(auth.qop[0], 'auth');
        expect(auth.algorithm, 'MD5');
        expect(auth.auth_params['otherk1'], 'other_v1');
      }),
  () => test('Parser: Event.', () {
        String data = 'Presence;Param1=QWe;paraM2';
        dynamic event = Grammar.parse(data, 'Event');

        print('event => $event');

        expect(event.event, 'presence');
        expect(event.params['param1'], 'QWe');
        expect(event.params['param2'], null);
      }),
  () => test('Parser: Session-Expires.', () {
        String data;
        dynamic session_expires;

        data = '180;refresher=uac';
        session_expires = Grammar.parse(data, 'Session_Expires');

        print('session_expires => $session_expires');

        expect(session_expires.expires, 180);
        expect(session_expires.refresher, 'uac');

        data = '210  ;   refresher  =  UAS ; foo  =  bar';
        session_expires = Grammar.parse(data, 'Session_Expires');

        print('session_expires => $session_expires');

        expect(session_expires.expires, 210);
        expect(session_expires.refresher, 'uas');
      }),
  () => test('Parser: Reason.', () {
        String data;
        dynamic reason;

        data = 'SIP  ; cause = 488 ; text = "Wrong SDP"';
        reason = Grammar.parse(data, 'Reason');

        print('reason => $reason');

        expect(reason.protocol, 'sip');
        expect(reason.cause, 488);
        expect(reason.text, 'Wrong SDP');

        data = 'ISUP; cause=500 ; LALA = foo';
        reason = Grammar.parse(data, 'Reason');

        print('reason => $reason');

        expect(reason.protocol, 'isup');
        expect(reason.cause, 500);
        expect(reason.text, null);
        expect(reason.params['lala'], 'foo');
      }),
  () => test('Parser: Refer-To.', () {
        String data;
        dynamic parsed;

        data = 'sip:alice@versatica.com';
        parsed = Grammar.parse(data, 'Refer_To');

        print('refer-to => $parsed');

        expect(parsed.uri.scheme, 'sip');
        expect(parsed.uri.user, 'alice');
        expect(parsed.uri.host, 'versatica.com');

        data =
            '<sip:bob@versatica.com?Accept-Contact=sip:bobsdesk.versatica.com>';
        parsed = Grammar.parse(data, 'Refer_To');

        print('refer-to => $parsed');

        expect(parsed.uri.scheme, 'sip');
        expect(parsed.uri.user, 'bob');
        expect(parsed.uri.host, 'versatica.com');
        expect(parsed.uri.hasHeader('Accept-Contact'), true);
      }),
  () => test('Parser: Replaces.', () {
        dynamic parsed;
        String data =
            '5t2gpbrbi72v79p1i8mr;to-tag=03aq91cl9n;from-tag=kun98clbf7';

        parsed = Grammar.parse(data, 'Replaces');

        print('replaces => $parsed');

        expect(parsed.call_id, '5t2gpbrbi72v79p1i8mr');
        expect(parsed.to_tag, '03aq91cl9n');
        expect(parsed.from_tag, 'kun98clbf7');
      }),
  () => test('Parser: absoluteURI.', () {
        dynamic parsed;
        String data = 'ws://127.0.0.1:4040/sip';

        parsed = Grammar.parse(data, 'absoluteURI');

        print('absoluteURI => $parsed');

        expect(parsed.scheme, 'ws');
        expect(parsed.port, 4040);
        expect(parsed.host, '127.0.0.1');
      }),
  () => test('Parser: rport.', () {
        String data =
            'SIP/2.0/WSS w1k06226skhf.invalid;rport=6231;received=xxx;branch=z9hG4bK443813988';
        ParsedData parsed = Grammar.parse(data, 'Via');

        print('rport => ${parsed.rport}');
        expect(parsed.rport, 6231);
        data =
            'SIP/2.0/WSS w1k06226skhf.invalid;rport=;received=xxx;branch=z9hG4bK443813988';
        parsed = Grammar.parse(data, 'Via');
        expect(<dynamic>[null, 0].contains(parsed.rport), true);

        data =
            'SIP/2.0/WSS w1k06226skhf.invalid;rport;received=xxx;branch=z9hG4bK443813988';
        parsed = Grammar.parse(data, 'Via');
        expect(parsed.rport, null);
      }),
  () => test('Parser: contact with none-domain.', () {
        String data = 'hello <sip:asterisk@8c2d06b92042:5060;transport=ws>';
        dynamic contacts = Grammar.parse(data, 'Contact');
        print('contacts => $contacts');
        dynamic c0 = contacts[0]['parsed'];
        expect(c0.uri.host, '8c2d06b92042');
      })
];

void main() {
  for (Function func in testFunctions) {
    func();
  }
}
