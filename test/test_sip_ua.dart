import 'dart:async';

import 'package:test/test.dart';

import 'package:sip_ua/src/config.dart' as config;
import 'package:sip_ua/src/event_manager/event_manager.dart';
import 'package:sip_ua/src/transports/socket_interface.dart';
import 'package:sip_ua/src/transports/web_socket.dart';
import 'package:sip_ua/src/ua.dart';

late UA ua;
void main() {
  test(' WebSocket: EchoTest', () async {
    Completer<dynamic> completer = Completer<dynamic>();
    config.Settings configuration = config.Settings();
    configuration.sockets = <SIPUASocketInterface>[
      SIPUAWebSocket('ws://127.0.0.1:5070/sip', messageDelay: 0)
    ];
    configuration.authorization_user = '100';
    configuration.password = '100';
    configuration.uri = 'sip:100@127.0.0.1';
    try {
      ua = UA(configuration);
      ua.on(EventSocketConnecting(), (EventSocketConnecting data) {
        print('connecting => $data');
      });

      ua.on<EventSocketConnected>(EventSocketConnected,
          (EventSocketConnected data) {
        print('connected => $data');
      });

      ua.on<EventSocketDisconnected>(EventSocketDisconnected,
          (EventSocketDisconnected data) {
        print('disconnected => $data');
      });
      ua.start();
    } catch (e) {
      print(e.toString());
    }
    return completer;
  });
}
