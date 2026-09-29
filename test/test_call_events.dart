import 'package:test/test.dart';

import 'package:sip_ua/src/enums.dart';
import 'package:sip_ua/src/event_manager/call_events.dart';

List<void Function()> testFunctions = <void Function()>[
  // Both constructors used to accept these arguments and silently drop them,
  // so listeners always saw null. A null unhold originator made apps treat
  // every local resume as remote-initiated and never tell the OS call UI.
  () => test('EventCallUnhold keeps its originator', () {
        expect(EventCallUnhold(originator: Originator.local).originator,
            Originator.local);
        expect(EventCallUnhold(originator: Originator.remote).originator,
            Originator.remote);
      }),
  () => test('EventCallHold keeps its originator', () {
        expect(EventCallHold(originator: Originator.local).originator,
            Originator.local);
      }),
  () => test('EventNewRTCSession keeps its originator and request', () {
        final Object request = Object();
        final EventNewRTCSession event =
            EventNewRTCSession(originator: Originator.remote, request: request);
        expect(event.originator, Originator.remote);
        expect(event.request, same(request));
      }),
];

void main() {
  for (void Function() func in testFunctions) {
    func();
  }
}
