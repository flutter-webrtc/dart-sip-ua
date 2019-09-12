import 'dart:io';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  runApp(ChangeNotifierProvider<SIPUAHelper>.value(
    value: SIPUAHelper(),
    child: MyApp(),
  ));
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
      ),
      initialRoute: '/dialpad',
      routes: {
        '/dialpad': (context) => DialPadWidget(),
        '/register': (context) => RegisterWidget(),
        '/callscreen': (context) => CallScreenWidget(),
        '/about': (context) => AboutWidget(),
      },
    );
  }
}
