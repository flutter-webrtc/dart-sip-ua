import 'dart:async';
import 'dart:io';

import 'package:sip_ua/src/event_manager/events.dart';
import 'package:sip_ua/src/transport.dart';
import 'package:sip_ua/src/transports/websocket_interface.dart';
import 'package:test/test.dart';

List<void Function()> testFunctions = <void Function()>[
  () => test(' WebSocket: EchoTest', () async {
        Completer<void> completer = Completer<void>();
        HttpServer.bind('127.0.0.1', 4040).then((HttpServer server) async {
          try {
            await for (HttpRequest req in server) {
              if (req.uri.path == '/sip') {
                // Upgrade a HttpRequest to a WebSocket connection.
                WebSocket socket = await WebSocketTransformer.upgrade(req);
                socket.listen((dynamic msg) {
                  socket.add(msg);
                  expect(msg, 'message');
                  socket.close();
                  server.close();
                });
              }
            }
          } catch (error) {
            print(' An error occurred. $error');
          }
        });

        WebSocketInterface client =
            WebSocketInterface('ws://127.0.0.1:4040/sip', messageDelay: 0);

        expect(client.url, 'ws://127.0.0.1:4040/sip');
        expect(client.via_transport, 'WS');
        expect(client.sip_uri, 'sip:127.0.0.1:4040;transport=ws');
        expect(client.isConnected(), false);

        client.onconnect = () {
          print('connected');
          client.send('message');
          expect(client.isConnected(), true);
        };
        client.ondata = (dynamic data) async {
          print('ondata => $data');
          expect(data, 'message');
          client.disconnect();
          completer.complete();
        };
        client.ondisconnect = (WebSocketInterface socket, bool error,
            int? closeCode, String? reason) {
          print(
              'ondisconnect => error $error [$closeCode] ${reason.toString()}');
          expect(client.isConnected(), false);
        };
        client.connect();
        return completer;
      }),
  () => test(' WebSocket: EchoTest', () async {
        Completer<void> completer = Completer<void>();
        HttpServer.bind('127.0.0.1', 4041).then((HttpServer server) async {
          try {
            await for (HttpRequest req in server) {
              if (req.uri.path == '/sip') {
                // Upgrade a HttpRequest to a WebSocket connection.
                WebSocket socket = await WebSocketTransformer.upgrade(req);
                socket.listen((dynamic msg) {
                  socket.add(msg);
                  expect(msg, 'message');
                  socket.close();
                  server.close();
                });
              }
            }
          } catch (error) {
            print(' An error occurred. $error');
          }
        });
        WebSocketInterface socket =
            WebSocketInterface('ws://127.0.0.1:4041/sip', messageDelay: 0);
        Transport trasnport = Transport(<WebSocketInterface>[socket]);

        trasnport.onconnecting = (WebSocketInterface? socket, int? attempt) {
          expect(trasnport.isConnecting(), true);
        };

        trasnport.onconnect = (Transport socket) {
          expect(trasnport.isConnected(), true);
          trasnport.send('message');
        };

        trasnport.ondata = (Transport transport, String messageData) {
          // expect(socket['message'], 'message');
          trasnport.disconnect();
        };

        trasnport.ondisconnect =
            (WebSocketInterface? socket, ErrorCause cause) {
          expect(trasnport.isConnected(), false);
          completer.complete();
        };

        trasnport.connect();

        return completer;
      })
];

void main() {
  for (Function func in testFunctions) {
    func();
  }
}
