import 'dart:io';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/webrtc.dart';
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
  var _sipUA;
  var _password;
  var _wsUri = 'wss://tryit.jssip.net:10443';
  var _sipUri = 'hello_flutter@tryit.jssip.net';
  var _displayName = 'Flutter SIP UA';
  var _dest = 'sip:111_6ackea@tryit.jssip.net';
  double _localVideoHeight;
  double _localVideoWidth;
  EdgeInsetsGeometry _localVideoMargin;
  RTCVideoRenderer _localRenderer = new RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = new RTCVideoRenderer();
  bool _registered = false;
  bool _haveRemoteVideo = false;

  _MyHomePageState();

  @override
  initState() {
    super.initState();
    _initRenders();
  }

  _initRenders() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

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

      this._sipUA.on('failed', (data) {
        this.setState(() {
          _localRenderer.srcObject = null;
          _remoteRenderer.srcObject = null;
          _haveRemoteVideo = false;
        });
      });

      this._sipUA.on('ended', (data) {
        this.setState(() {
          _localRenderer.srcObject = null;
          _remoteRenderer.srcObject = null;
          _haveRemoteVideo = false;
        });
      });

      this._sipUA.on('stream', (data) {
        var stream = data['stream'];
        if (data['originator'] == 'local') {
          _localRenderer.srcObject = stream;
        }
        if (data['originator'] == 'remote') {
          _remoteRenderer.srcObject = stream;
          _haveRemoteVideo = true;
        }
        this.setState(() {
          _resizeLocalVideo();
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

  _handleCall() {
    if (!inCalling)
      this._sipUA.connect(_dest);
    else
      this._sipUA.answer();
  }

  _handleHangup() {
    if (inCalling) this._sipUA.hangup();
    setState(() {
      _resizeLocalVideo();
    });
  }

  get inCalling => this._sipUA.session != null;

  _resizeLocalVideo() {
    _localVideoMargin = _haveRemoteVideo
        ? EdgeInsets.only(bottom: 15, left: 15)
        : EdgeInsets.all(0);
    _localVideoWidth = _haveRemoteVideo
        ? MediaQuery.of(context).size.width / 4
        : MediaQuery.of(context).size.width;
    _localVideoHeight = _haveRemoteVideo
        ? MediaQuery.of(context).size.height / 4
        : MediaQuery.of(context).size.height;
  }

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

  Widget buildCallingView() {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Center(
            child: RTCVideoView(_remoteRenderer),
          ),
          Container(
            child: AnimatedContainer(
              child: RTCVideoView(_localRenderer),
              height: _localVideoHeight,
              width: _localVideoWidth,
              alignment: Alignment.bottomLeft,
              duration: Duration(milliseconds: 350),
              margin: _localVideoMargin,
            ),
            alignment: Alignment.bottomLeft,
          ),
        ],
      ),
      floatingActionButton: new FloatingActionButton(
        backgroundColor: Colors.red,
        onPressed: _handleHangup,
        tooltip: 'Hangup',
        child: new Icon(Icons.call_end),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: _registered
            ? <Widget>[
                new PopupMenuButton<String>(
                    onSelected: (String value) {
                      setState(() {
                        if (value == 'logout') {
                          _handleLogout();
                        }
                      });
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
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
              ]
            : null,
      ),
      body: Center(
        child: !_registered
            ? buildLoginView(context)
            : inCalling ? buildCallingView() : buildDialView(),
      ),
    );
  }
}
