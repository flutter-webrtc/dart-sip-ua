import 'dart:async';
import 'dart:io';

void main() async {
  TestWebsocket2 tester = TestWebsocket2();
  tester.connect('wss://echo.websocket.org/');

  await tester.finished.future;
}

class TestWebsocket2 {
  bool connected = false;
  late WebSocket ws;
  late Completer<String> completer;
  int ctr = 1;

  Completer<String> finished = Completer<String>();

  void send() {
    String message = 'A' * ctr;
    ws.add(message);
    completer = Completer<String>();
    completer.future.then((dynamic t) {
      ctr += 7;
      if (ctr > 5000 || finished.isCompleted) {
        finished.complete('');
      } else {
        send();
      }
    });
  }

  void connect(String url) async {
    ws = await WebSocket.connect(url);
    connected = true;
    ws.listen((dynamic data) {
      _onMessage(data as String);
    }, onDone: () {
      print('Closed by server [${ws.closeCode}, ${ws.closeReason}]!');
      connected = false;
    });
    send();
  }

  void _onMessage(String data) {
    print('Received data of size ${data.length} expected $ctr');
    if (data.length != ctr) {
      finished.complete('');
    }
    completer.complete('');
  }
}
