import 'package:sip_ua/src/UA.dart';
import 'package:test/test.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:sip_ua/src/Config.dart' as config;
import 'package:sip_ua/src/WebSocketInterface.dart';
import 'dart:async';
import 'package:sip_ua/src/event_manager/event_manager.dart';

var ua;
void main() {
  test("WebSocket: EchoTest", () async {
    var completer = new Completer();
    var configuration = new config.Settings();
    configuration.sockets = [new WebSocketInterface('ws://127.0.0.1:5070/sip')];
    configuration.authorization_user = '100';
    configuration.password = '100';
    configuration.uri = 'sip:100@127.0.0.1';
    try {
      ua = new UA(configuration);
      ua.on(EventSocketConnecting(), (EventSocketConnecting data) {
        print('connecting => ' + data.toString());
      });

      ua.on(EventSocketConnected, (EventSocketConnected data) {
        print('connected => ' + data.toString());
      });

      ua.on(EventSocketDisconnected, (EventSocketDisconnected data) {
        print('disconnected => ' + data.toString());
      });
      ua.start();
    } catch (e) {
      print(e.toString());
    }
    return completer;
  });
}
