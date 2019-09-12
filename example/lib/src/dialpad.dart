import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sip_ua_helper.dart';

class DialPadWidget extends StatefulWidget {
  DialPadWidget({Key key}) : super(key: key);
  @override
  _MyDialPadWidget createState() => _MyDialPadWidget();
}

class _MyDialPadWidget extends State<DialPadWidget> {
  var _dest = 'sip:111_6ackea@tryit.jssip.net';
  _handleCall(context) {
    Provider.of<SIPUAHelper>(context).connect(_dest);
    Navigator.pushNamed(context, '/callscreen');
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
                    padding: const EdgeInsets.all(48.0),
                    child: Center(
                        child: Text(
                      'Register Status: ${Provider.of<SIPUAHelper>(context).registerState}',
                      style: TextStyle(fontSize: 18, color: Colors.black54),
                    )),
                  ),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(48.0, 0, 48.0, 18.0),
                      child: TextField(
                        keyboardType: TextInputType.text,
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          contentPadding: EdgeInsets.all(10.0),
                          border: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.black12)),
                          hintText: _dest ?? 'Enter SIP URL or username',
                        ),
                        onChanged: (value) {
                          setState(() {
                            _dest = value;
                          });
                        },
                      )),
                  Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Container(
                          height: 48.0,
                          width: 160.0,
                          child: MaterialButton(
                            child: Text(
                              'CALL',
                              style: TextStyle(
                                  fontSize: 16.0, color: Colors.white),
                            ),
                            color: Colors.blue,
                            textColor: Colors.white,
                            onPressed: () {
                              if (_dest != null) {
                                _handleCall(context);
                                return;
                              }
                              showDialog<Null>(
                                context: context,
                                barrierDismissible: false,
                                builder: (BuildContext context) {
                                  return new AlertDialog(
                                    title: new Text('Target is empty.'),
                                    content: new Text(
                                        'Please enter a SIP URI or username!'),
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
                          )))
                ])));
  }
}
