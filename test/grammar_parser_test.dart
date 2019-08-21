import 'package:test/test.dart';
import 'package:sip_ua/src/grammar_parser.dart';

void main() {
  var parser = new GrammarParser('');

   test("parser: host/domain/ipv4/ipv6",(){
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
   });
}