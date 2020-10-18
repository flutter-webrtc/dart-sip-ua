import 'dart:async';

import 'package:sip_ua/src/config.dart' as config;
import 'package:sip_ua/src/event_manager/event_manager.dart';
import 'package:sip_ua/src/transports/websocket_interface.dart';
import 'package:sip_ua/src/ua.dart';
import 'package:test/test.dart';

UA ua;
void main() {
  test(' WebSocket: EchoTest', () async {
    Completer<dynamic> completer = Completer<dynamic>();
    config.Settings configuration = config.Settings();
    configuration.sockets = <WebSocketInterface>[
      WebSocketInterface('ws://127.0.0.1:5070/sip')
    ];
    configuration.authorization_user = '100';
    configuration.password = '100';
    configuration.uri = 'sip:100@127.0.0.1';
    try {
      ua = UA(configuration);
      ua.on(EventSocketConnecting(), (EventSocketConnecting data) {
        print('connecting => ' + data.toString());
      });

      ua.on<EventSocketConnected>(EventSocketConnected,
          (EventSocketConnected data) {
        print('connected => ' + data.toString());
      });

      ua.on<EventSocketDisconnected>(EventSocketDisconnected,
          (EventSocketDisconnected data) {
        print('disconnected => ' + data.toString());
      });
      ua.start();
    } catch (e) {
      print(e.toString());
    }
    return completer;
  });
}
