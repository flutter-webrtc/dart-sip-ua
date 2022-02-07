import 'package:sip_ua/src/parser.dart';
import 'package:test/test.dart';

import 'data/sip_message.dart';

List<void Function()> testFunctions = <void Function()>[
  () => test('SIP Message Parser: request.', () {
        dynamic parsed = parseMessage(request, null);
        expect(parsed.method, 'REGISTER');
        expect(parsed.call_id, 'b3b4vt3rhfruq8nsm980uv');
        expect(parsed.cseq, 1);
        expect(parsed.via_branch, 'z9hG4bK3625642');
        expect(parsed.from.toString(),
            '"111" <sip:111_6ackea@tryit.jssip.net>;tag=6mo6me6ask');
        expect(parsed.to.toString(), '<sip:111_6ackea@tryit.jssip.net>');
      }),
  () => test('SIP Message Parser: response.', () {
        dynamic parsed = parseMessage(response, null);
        expect(parsed.method, 'REGISTER');
        expect(parsed.call_id, '2q7hmiai46q45vc4ao8tmn');
        expect(parsed.reason_phrase, 'OK');
        expect(parsed.status_code, 200);
        expect(parsed.to_tag, 'ebec76fc69a1b64d3ac8a167a40d8ff6.0b00');
      }),
  () => test('SIP Message Parser: request with sdp.', () {
        dynamic parsed = parseMessage(request_with_sdp, null);
        //print('body => ' + parsed.body);
        expect(parsed.method, 'INVITE');
        //var sdp = parsed.parseSDP();
        //print('sdp -> ' + sdp.toString());
      }),
  () => test('SIP Message Parser: 100 trying.', () {
        dynamic parsed = parseMessage(trying, null);
        expect(parsed.status_code, 100);
      }),
  () => test('SIP Message Parser: ack.', () {
        dynamic parsed = parseMessage(ack, null);
        expect(parsed.method, 'ACK');
      }),
  () => test('SIP Message Parser: 404.', () {
        dynamic parsed = parseMessage(notFound, null);
        expect(parsed.status_code, 404);
      })
];

void main() {
  //testFunctions.forEach((func) => func());
  testFunctions[0]();
}
