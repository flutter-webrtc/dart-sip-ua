import 'package:flutter/material.dart';
import 'sip_ua_helper.dart';

class DialPadWidget extends StatefulWidget {
  SIPUAHelper _helper;
  DialPadWidget(this._helper, {Key key}) : super(key: key);
  @override
  _MyDialPadWidget createState() => _MyDialPadWidget();
}

class _MyDialPadWidget extends State<DialPadWidget> {
  var _dest = 'sip:111_6ackea@tryit.jssip.net';
  get helper => widget._helper;
  TextEditingController _textController;

  @override
  initState() {
    super.initState();
    _textController = new TextEditingController(text: _dest);
    _textController.text = _dest;
    _bindEventListeners();
  }

  _handleRegisterState(state, data) {
    this.setState(() {});
  }

  _bindEventListeners() {
    helper.on('registerState', _handleRegisterState);
    helper.on('uaState', (state, data) {
      if (state == 'newRTCSession') Navigator.pushNamed(context, '/callscreen');
    });
  }

  _handleCall(context) {
    var dest = _textController.text;
    if (dest == null || dest.length == 0) {
      showDialog<Null>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return new AlertDialog(
            title: new Text('Target is empty.'),
            content: new Text('Please enter a SIP URI or username!'),
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
    }
    helper.connect(dest);
  }

  _handleBackSpace() {
    var text = _textController.text;
    if (text.length > 0) {
      this.setState(() {
        text = text.substring(0, text.length - 1);
        _textController.text = text;
      });
    }
  }

  _handleNum(number) {
    this.setState(() {
      _textController.text += number;
    });
  }

  _buildDialPad() {
    var lables = [
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

    return [
      Container(
          child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Container(
                        width: 280,
                        child: TextField(
                          keyboardType: TextInputType.text,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 28, color: Colors.black54),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                          ),
                          controller: _textController,
                        )),
                  ]))),
      new Container(
          child: new Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: lables
                  .map((row) => new Padding(
                      padding: const EdgeInsets.all(3),
                      child: new Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: row
                              .map((label) => new Container(
                                  height: 64,
                                  width: 64,
                                  child: new FlatButton(
                                    //heroTag: "num_$label",
                                    shape: CircleBorder(),
                                    child: new Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: <Widget>[
                                          Text('${label.keys.first}',
                                              style: TextStyle(
                                                  fontSize: 28,
                                                  color: Theme.of(context)
                                                      .accentColor)),
                                          Text('${label.values.first}'.toUpperCase(),
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Theme.of(context)
                                                      .disabledColor))
                                        ]),
                                    onPressed: () => _handleNum(label.keys.first),
                                  )))
                              .toList())))
                  .toList())),
      Container(
          child: new Row(
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
            onPressed: () => _handleCall(context),
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
            new PopupMenuButton<String>(
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
                        child: new Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                              child: new Icon(
                                Icons.account_circle,
                                color: Colors.black38,
                              ),
                            ),
                            SizedBox(
                              child: new Text('Account'),
                              width: 64,
                            )
                          ],
                        ),
                        value: 'account',
                      ),
                      PopupMenuItem(
                        child: new Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: <Widget>[
                            new Icon(
                              Icons.info,
                              color: Colors.black38,
                            ),
                            SizedBox(
                              child: new Text('About'),
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
                    padding: const EdgeInsets.all(24.0),
                    child: Center(
                        child: Text(
                      'Status: ${helper.registerState}',
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    )),
                  ),
                  new Container(
                      width: 300,
                      child: new Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: _buildDialPad(),
                      )),
                ])));
  }
}
