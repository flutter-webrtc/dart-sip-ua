import 'dart:io';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;

import 'package:flutter/material.dart';
import 'src/sip_ua_helper.dart';
import 'src/register.dart';
import 'src/dialpad.dart';
import 'src/callscreen.dart';
import 'src/about.dart';

bool isMobile() {
  return Platform.isAndroid || Platform.isIOS;
}

bool isDesktop() {
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

void main() {
  if (isDesktop()) debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
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
