import 'dart:io';

import 'package:test/test.dart';

List<void Function()> testFunctions = <void Function()>[
  () => test('Parser: URI => [ replace scheme ].', () {
        String url = 'wss://github.com:8086/ws';
        Uri uri = Uri.parse(url);
        expect(uri.scheme, 'wss');
        Uri uri2 = uri.replace(
            scheme: uri.scheme == 'wss' ? 'https' : 'http', path: '/wsxxx');
        expect(uri.scheme, 'wss');
        expect(uri2.scheme, 'https');
      })
];

void main() {
  for (Function func in testFunctions) {
    func();
  }
}
