import 'dart:io';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'sip_ua_helper.dart';

bool isMobile() {
  return Platform.isAndroid || Platform.isIOS;
}

bool isDesktop() {
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

void main() {
  if (isDesktop()) debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
  runApp(new MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        // See https://github.com/flutter/flutter/wiki/Desktop-shells#fonts
        fontFamily: 'Roboto',
      ),
      home: MyHomePage(title: 'Dart SIP UA Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  var _sipUA;
  var _password;
  var _bodyText;
  var _wsUri = 'wss://tryit.jssip.net:10443';
  var _sipUri = 'hello_flutter@tryit.jssip.net';
  var _displayName = 'Flutter SIP UA';
  var _dest;

  bool _registered = false;

  _MyHomePageState() {}

  void _handleLogin() {
    if (_sipUA == null) {
      this._sipUA = new SIPUAHelper(_wsUri, {
        'Origin': ' https://tryit.jssip.net',
        'Host': 'tryit.jssip.net:10443'
      });
      this._sipUA.start(_sipUri, _password, _displayName);
      this._sipUA.on('registered', (data) {
        setState(() {
          _registered = true;
        });
      });
      this._sipUA.on('unregistered', (data) {
        setState(() {
          _registered = false;
        });
      });
    } else {
      this._sipUA.register();
    }
  }

  _handleLogout() {
    if (this._sipUA != null) {
      this._sipUA.unregister();
    }
  }

  _handleCall() {}

  Widget buildLoginView(context) {
    return new Align(
        alignment: Alignment(0, 0),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                  width: 260.0,
                  child: TextField(
                    keyboardType: TextInputType.text,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      contentPadding: EdgeInsets.all(10.0),
                      border: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black12)),
                      hintText: _wsUri ?? 'WebSocket URL',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _wsUri = value;
                      });
                    },
                  )),
              SizedBox(
                  width: 260.0,
                  child: TextField(
                    keyboardType: TextInputType.text,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      contentPadding: EdgeInsets.all(10.0),
                      border: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black12)),
                      hintText: _sipUri ?? 'SIP URI',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _sipUri = value;
                      });
                    },
                  )),
              SizedBox(
                  width: 260.0,
                  child: TextField(
                    keyboardType: TextInputType.text,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      contentPadding: EdgeInsets.all(10.0),
                      border: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black12)),
                      hintText: _password ?? 'Enter Password',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _password = value;
                      });
                    },
                  )),
              SizedBox(width: 260.0, height: 48.0),
              SizedBox(
                  width: 220.0,
                  height: 48.0,
                  child: MaterialButton(
                    child: Text(
                      'Login',
                      style: TextStyle(fontSize: 16.0, color: Colors.white),
                    ),
                    color: Colors.blue,
                    textColor: Colors.white,
                    onPressed: () {
                      if (_sipUri != null) {
                        _handleLogin();
                        return;
                      }
                      showDialog<Null>(
                        context: context,
                        barrierDismissible: false,
                        builder: (BuildContext context) {
                          return new AlertDialog(
                            title: new Text('URI is empty'),
                            content: new Text('Please enter SIP URI!'),
                            actions: <Widget>[
                              new FlatButton(
                                child: new Text('Ok'),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ))
            ]));
  }

  Widget buildDialView() {
    return new Align(
        alignment: Alignment(0, 0),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                  width: 260.0,
                  child: TextField(
                    keyboardType: TextInputType.text,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      contentPadding: EdgeInsets.all(10.0),
                      border: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black12)),
                      hintText: _dest ?? 'SIP URL or username',
                    ),
                    onChanged: (value) {
                      setState(() {
                        _dest = value;
                      });
                    },
                  )),
              SizedBox(width: 260.0, height: 48.0),
              SizedBox(
                  width: 220.0,
                  height: 48.0,
                  child: MaterialButton(
                    child: Text(
                      'CALL',
                      style: TextStyle(fontSize: 16.0, color: Colors.white),
                    ),
                    color: Colors.blue,
                    textColor: Colors.white,
                    onPressed: () {
                      if (_dest != null) {
                        _handleCall();
                        return;
                      }
                      showDialog<Null>(
                        context: context,
                        barrierDismissible: false,
                        builder: (BuildContext context) {
                          return new AlertDialog(
                            title: new Text('Target is empty.'),
                            content:
                                new Text('Please enter a SIP URI or username!'),
                            actions: <Widget>[
                              new FlatButton(
                                child: new Text('Ok'),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ))
            ]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions:  _registered ? <Widget>[
          new PopupMenuButton<String>(
              onSelected: (String value) {
                setState(() {
                  if (value == 'logout') {
                    _handleLogout();
                  }
                });
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem(
                      child: new Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          new Text('Logout'),
                          new Icon(Icons.remove_circle)
                        ],
                      ),
                      value: 'logout',
                    )
                  ])
        ] : null,
      ),
      body: Center(
        child: _registered ? buildDialView() : buildLoginView(context),
      ),
    );
  }
}
