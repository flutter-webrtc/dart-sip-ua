import 'package:test/test.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:sip_ua/src/Config.dart' as config;
import 'package:sip_ua/src/WebSocketInterface.dart';
import 'dart:async';

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
      ua.on('connecting',(data){
        print('connecting => ' + data.toString());
      });

      ua.on('connected',(data){
        print('connected => ' + data.toString());
      });

      ua.on('disconnected',(data){
        print('disconnected => ' + data.toString());
      });
      ua.start();
    } catch (e) {
      print(e.toString());
    }
    return completer;
  });
}
