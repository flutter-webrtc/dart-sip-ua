import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sip_ua/sip_ua.dart';

import 'widgets/action_button.dart';

class DialPadWidget extends StatefulWidget {
  final SIPUAHelper? _helper;
  DialPadWidget(this._helper, {Key? key}) : super(key: key);
  @override
  _MyDialPadWidget createState() => _MyDialPadWidget();
}

class _MyDialPadWidget extends State<DialPadWidget>
    implements SipUaHelperListener {
  String? _dest;
  SIPUAHelper? get helper => widget._helper;
  TextEditingController? _textController;
  late SharedPreferences _preferences;

  String? receivedMsg;

  @override
  initState() {
    super.initState();
    receivedMsg = "";
    _bindEventListeners();
    _loadSettings();
  }

  void _loadSettings() async {
    _preferences = await SharedPreferences.getInstance();
    _dest = _preferences.getString('dest') ?? 'sip:hello_jssip@tryit.jssip.net';
    _textController = TextEditingController(text: _dest);
    _textController!.text = _dest!;

    setState(() {});
  }

  void _bindEventListeners() {
    helper!.addSipUaHelperListener(this);
  }

  Future<Widget?> _handleCall(BuildContext context,
      [bool voiceOnly = false]) async {
    var dest = _textController?.text;
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      await Permission.microphone.request();
      await Permission.camera.request();
    }
    if (dest == null || dest.isEmpty) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Target is empty.'),
            content: Text('Please enter a SIP URI or username!'),
            actions: <Widget>[
              TextButton(
                child: Text('Ok'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
      return null;
    }

    final mediaConstraints = <String, dynamic>{'audio': true, 'video': true};

    MediaStream mediaStream;

    if (kIsWeb && !voiceOnly) {
      mediaStream =
          await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      mediaConstraints['video'] = false;
      MediaStream userStream =
          await navigator.mediaDevices.getUserMedia(mediaConstraints);
      mediaStream.addTrack(userStream.getAudioTracks()[0], addToNative: true);
    } else {
      mediaConstraints['video'] = !voiceOnly;
      mediaStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    }

    helper!.call(dest, voiceonly: voiceOnly, mediaStream: mediaStream);
    _preferences.setString('dest', dest);
    return null;
  }

  void _handleBackSpace([bool deleteAll = false]) {
    var text = _textController!.text;
    if (text.isNotEmpty) {
      setState(() {
        text = deleteAll ? '' : text.substring(0, text.length - 1);
        _textController!.text = text;
      });
    }
  }

  void _handleNum(String number) {
    setState(() {
      _textController!.text += number;
    });
  }

  List<Widget> _buildNumPad() {
    var labels = [
      [
        {'1': ''},
        {'2': 'abc'},
        {'3': 'def'}
      ],
      [
        {'4': 'ghi'},
        {'5': 'jkl'},
        {'6': 'mno'}
      ],
      [
        {'7': 'pqrs'},
        {'8': 'tuv'},
        {'9': 'wxyz'}
      ],
      [
        {'*': ''},
        {'0': '+'},
        {'#': ''}
      ],
    ];

    return labels
        .map((row) => Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: row
                    .map((label) => ActionButton(
                          title: label.keys.first,
                          subTitle: label.values.first,
                          onPressed: () => _handleNum(label.keys.first),
                          number: true,
                        ))
                    .toList())))
        .toList();
  }

  List<Widget> _buildDialPad() {
    return [
      Container(
          width: 360,
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                    width: 360,
                    child: TextField(
                      keyboardType: TextInputType.text,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, color: Colors.black54),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                      ),
                      controller: _textController,
                    )),
              ])),
      Container(
          width: 300,
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: _buildNumPad())),
      Container(
          width: 300,
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  ActionButton(
                    icon: Icons.videocam,
                    onPressed: () => _handleCall(context),
                  ),
                  ActionButton(
                    icon: Icons.dialer_sip,
                    fillColor: Colors.green,
                    onPressed: () => _handleCall(context, true),
                  ),
                  ActionButton(
                    icon: Icons.keyboard_arrow_left,
                    onPressed: () => _handleBackSpace(),
                    onLongPress: () => _handleBackSpace(true),
                  ),
                ],
              )))
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("Dart SIP UA Demo"),
          actions: <Widget>[
            PopupMenuButton<String>(
                onSelected: (String value) {
                  switch (value) {
                    case 'account':
                      Navigator.pushNamed(context, '/register');
                      break;
                    case 'about':
                      Navigator.pushNamed(context, '/about');
                      break;
                    default:
                      break;
                  }
                },
                icon: Icon(Icons.menu),
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                      PopupMenuItem(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                              child: Icon(
                                Icons.account_circle,
                                color: Colors.black38,
                              ),
                            ),
                            SizedBox(
                              child: Text('Account'),
                              width: 64,
                            )
                          ],
                        ),
                        value: 'account',
                      ),
                      PopupMenuItem(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: <Widget>[
                            Icon(
                              Icons.info,
                              color: Colors.black38,
                            ),
                            SizedBox(
                              child: Text('About'),
                              width: 64,
                            )
                          ],
                        ),
                        value: 'about',
                      )
                    ]),
          ],
        ),
        body: Align(
            alignment: Alignment(0, 0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Center(
                        child: Text(
                      'Status: ${EnumHelper.getName(helper!.registerState.state)}',
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    )),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Center(
                        child: Text(
                      'Received Message: $receivedMsg',
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    )),
                  ),
                  Container(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _buildDialPad(),
                  )),
                ])));
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    setState(() {});
  }

  @override
  void transportStateChanged(TransportState state) {}

  @override
  void callStateChanged(Call call, CallState callState) {
    if (callState.state == CallStateEnum.CALL_INITIATION) {
      Navigator.pushNamed(context, '/callscreen', arguments: call);
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    //Save the incoming message to DB
    String? msgBody = msg.request.body as String?;
    setState(() {
      receivedMsg = msgBody;
    });
  }

  @override
  void onNewNotify(Notify ntf) {}
}
