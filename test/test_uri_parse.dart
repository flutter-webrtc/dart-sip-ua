import 'dart:io';
import 'package:test/test.dart';

var testFunctions = [
  () => test('Parser: URI => [ replace scheme ].', () {
        var url = 'wss://github.com:8086/ws';
        var uri = Uri.parse(url);
        expect(uri.scheme, 'wss');
        var uri2 = uri.replace(
            scheme: uri.scheme == 'wss' ? 'https' : 'http', path: '/wsxxx');
        expect(uri.scheme, 'https');
      })
];

void main() {
  testFunctions.forEach((func) => func());
}
