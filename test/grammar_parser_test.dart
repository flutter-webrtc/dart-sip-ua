import 'package:test/test.dart';
import 'package:sip_ua/src/grammar_parser.dart';
import 'package:sip_ua/src/URI.dart';
import 'package:sip_ua/src/NameAddrHeader.dart';

var testFunctions = [
  () => test("Parser: Host => [ domain, ipv4, ipv6 ].", () {
        var parser = new GrammarParser('');
        var data = parser.parse('www.google.com', 'host');
        expect(data['host_type'], 'domain');

        data = parser.parse('www.163.com', 'host');
        expect(data['host_type'], 'domain');

        data = parser.parse('myhost123', 'host');
        expect(data['host_type'], 'domain');

        data = parser.parse('localhost', 'host');
        expect(data['host_type'], 'domain');

        data = parser.parse('1.2.3.4.bar.qwe-asd.foo', 'host');
        expect(data['host_type'], 'domain');

        data = parser.parse('192.168.0.1', 'host');
        expect(data['host_type'], 'IPv4');

        data = parser.parse('127.0.0.1', 'host');
        expect(data['host_type'], 'IPv4');

        data = parser.parse('[::1]', 'host');
        expect(data['host_type'], 'IPv6');

        data = parser.parse('[1:0:fF::432]', 'host');
        expect(data['host_type'], 'IPv6');
      }),
  () => test("Parser: URI.", () {
        const uriData =
            'siP:%61liCE@versaTICA.Com:6060;TRansport=TCp;Foo=ABc;baz?X-Header-1=AaA1&X-Header-2=BbB&x-header-1=AAA2';
        URI uri = URI.parse(uriData);
        print('uri1 => ' + uriData);
        print('uri2 => ' + uri.toString());
        expect(uri.scheme, 'sip');
        expect(uri.user, 'aliCE');
        expect(uri.port, 6060);
        expect(uri.hasParam('transport'), true);
        expect(uri.hasParam('nooo'), false);
        expect(uri.getParam('transport'), 'tcp');

        expect(uri.getParam('foo'), 'ABc');
        expect(uri.getParam('baz'), null);
        expect(uri.getParam('nooo'), null);
        //test.deepEqual(uri.getHeader('x-header-1'), [ 'AaA1', 'AAA2' ]);
        //test.deepEqual(uri.getHeader('X-HEADER-2'), [ 'BbB' ]);
        expect(uri.getHeader('nooo'), null);
        print('uri3 => ' + uri.toString());
        expect(uri.toString(),
            'sip:aliCE@versatica.com:6060;transport=tcp;foo=ABc;baz?X-Header-1=AaA1&X-Header-1=AAA2&X-Header-2=BbB');
        expect(uri.toAor(show_port: true), 'sip:aliCE@versatica.com:6060');

        // Alter data.
        uri.user = 'Iñaki:PASSWD';
        expect(uri.user, 'Iñaki:PASSWD');
        expect(uri.deleteParam('foo'), 'ABc');
        uri.deleteHeader('x-header-1');
        //test.deepEqual(uri.deleteHeader('x-header-1'), [ 'AaA1', 'AAA2' ]);
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
  () => test("Parser: NameAddr with token display_name.", () {
        const data =
            'Foo    Foo Bar\tBaz<SIP:%61liCE@versaTICA.Com:6060;TRansport=TCp;Foo=ABc;baz?X-Header-1=AaA1&X-Header-2=BbB&x-header-1=AAA2>;QWE=QWE;ASd';
        NameAddrHeader name = NameAddrHeader.parse(data);
        print('name_addr_header => ' + name.toString());
      }),
  () => test("Parser: NameAddr with no space between DQUOTE and LAQUOT.", () {
        const data =
            '"Foo"<SIP:%61liCE@versaTICA.Com:6060;TRansport=TCp;Foo=ABc;baz?X-Header-1=AaA1&X-Header-2=BbB&x-header-1=AAA2>;QWE=QWE;ASd';
        NameAddrHeader name = NameAddrHeader.parse(data);
        print('name_addr_header => ' + name.toString());
        expect(name.display_name, 'Foo');
      }),
  () => test("Parser: NameAddr with no space between DQUOTE and LAQUOT", () {
        const data =
            '<SIP:%61liCE@versaTICA.Com:6060;TRansport=TCp;Foo=ABc;baz?X-Header-1=AaA1&X-Header-2=BbB&x-header-1=AAA2>;QWE=QWE;ASd';
        NameAddrHeader name = NameAddrHeader.parse(data);
        print('name_addr_header => ' + name.toString());
      }),
  () => test("Parser: NameAddr.", () {
        const data =
            '  "Iñaki ðđøþ foo \\"bar\\" \\\\\\\\ \\\\ \\\\d \\\\\\\\d \\\\\' \\\\\\"sdf\\\\\\""  ' +
                '<SIP:%61liCE@versaTICA.Com:6060;TRansport=TCp;Foo=ABc;baz?X-Header-1=AaA1&X-Header-2=BbB&x-header-1=AAA2>;QWE=QWE;ASd';
        NameAddrHeader name = NameAddrHeader.parse(data);
        print('name_addr_header => ' + name.toString());
        expect(name.display_name, 'Iñaki ðđøþ foo \\"bar\\" \\\\\\\\ \\\\ \\\\d \\\\\\\\d \\\\\' \\\\\\"sdf\\\\\\"');
      }),
  () => test("Parser: multiple Contact.", () {}),
  () => test("Parser: Via.", () {}),
  () => test("Parser: CSeq.", () {}),
  () => test("Parser: authentication challenge.", () {}),
  () => test("Parser: Event.", () {}),
  () => test("Parser: Session-Expires.", () {}),
  () => test("Parser: Reason.", () {}),
  () => test("Parser: Refer-To.", () {}),
  () => test("Parser: Replaces.", () {})
];

void main() {
  testFunctions.forEach((func) {
    func();
  });
}
