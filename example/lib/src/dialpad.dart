import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widgets/numpad.dart';
import 'package:sip_ua/sip_ua.dart';

class DialPadWidget extends StatefulWidget {
  final SIPUAHelper _helper;
  DialPadWidget(this._helper, {Key key}) : super(key: key);
  @override
  _MyDialPadWidget createState() => _MyDialPadWidget();
}

class _MyDialPadWidget extends State<DialPadWidget>
    implements SipUaHelperListener {
  String _dest;
  SIPUAHelper get helper => widget._helper;
  TextEditingController _textController;
  SharedPreferences prefs;

  @override
  initState() {
    super.initState();
    _bindEventListeners();
    _loadSettings();
  }

  void _loadSettings() async {
    prefs = await SharedPreferences.getInstance();
    _dest = prefs.getString('dest') ?? 'sip:111_6ackea@tryit.jssip.net';
    _textController = TextEditingController(text: _dest);
    _textController.text = _dest;
    this.setState(() {});
  }

  void _bindEventListeners() {
    helper.addSipUaHelperListener(this);
  }

  Widget _handleCall(BuildContext context, [bool voiceonly = false]) {
    var dest = _textController.text;
    if (dest == null || dest.isEmpty) {
      showDialog<Null>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Target is empty.'),
            content: Text('Please enter a SIP URI or username!'),
            actions: <Widget>[
              FlatButton(
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
    helper.call(dest, voiceonly);
    prefs.setString('dest', dest);
    return null;
  }

  void _handleBackSpace() {
    var text = _textController.text;
    if (text.isNotEmpty) {
      this.setState(() {
        text = text.substring(0, text.length - 1);
        _textController.text = text;
      });
    }
  }

  void _handleNum(String number) {
    this.setState(() {
      _textController.text += number;
    });
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
      NumPad(onPressed: (number) => _handleNum(number)),
      Container(
          width: 300,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              IconButton(
                icon: Icon(Icons.videocam, color: Colors.grey),
                onPressed: () => _handleCall(context),
              ),
              FloatingActionButton(
                heroTag: "audio_call",
                child: Icon(Icons.dialer_sip),
                backgroundColor: Colors.green,
                onPressed: () => _handleCall(context, true),
              ),
              IconButton(
                icon: Icon(Icons.backspace, color: Colors.grey),
                onPressed: () => _handleBackSpace(),
              ),
            ],
          ))
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
                      'Status: ${EnumHelper.getName(helper.registerState)}',
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
  void registrationStateChanged(RegistrationStateEnum state) {
    this.setState(() {});
  }

  @override
  void callStateChanged(CallState callState) {
    if (callState.state == CallStateEnum.CALL_INITIATION) {
      Navigator.pushNamed(context, '/callscreen');
    }
  }
}
