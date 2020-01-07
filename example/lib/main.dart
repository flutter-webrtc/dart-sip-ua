import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;

import 'package:flutter/material.dart';
import 'package:sip_ua/sip_ua.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'src/register.dart';
import 'src/dialpad.dart';
import 'src/callscreen.dart';
import 'src/about.dart';

void main() {
  if (WebRTC.platformIsDesktop) {
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
  }
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final SIPUAHelper _helper = SIPUAHelper();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => DialPadWidget(_helper),
        '/register': (context) => RegisterWidget(_helper),
        '/callscreen': (context) => CallScreenWidget(_helper),
        '/about': (context) => AboutWidget(),
      },
    );
  }
}
