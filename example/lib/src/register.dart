import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sip_ua_helper.dart';

class RegisterWidget extends StatefulWidget {
  SIPUAHelper _helper;
  RegisterWidget(this._helper, {Key key}) : super(key: key);
  @override
  _MyRegisterWidget createState() => _MyRegisterWidget();
}

class _MyRegisterWidget extends State<RegisterWidget> {
  var _password;
  var _wsUri;
  var _sipUri;
  var _displayName;
  var _wsExtraHeaders = {
    'Origin': ' https://tryit.jssip.net',
    'Host': 'tryit.jssip.net:10443'
  };
  SharedPreferences prefs;
  var _registerState;

  get helper => widget._helper;

  @override
  initState() {
    super.initState();
    _registerState = helper.registerState;
    helper.on('registerState', _handleRegisterState);
    helper.on('socketState', _handleSocketState);
    _loadSettings();
  }

  @override
  deactivate() {
    super.deactivate();
    helper.remove('registerState', _handleRegisterState);
    helper.remove('socketState', _handleSocketState);
    _saveSettings();
  }

  _loadSettings() async {
    prefs = await SharedPreferences.getInstance();
    _wsUri = prefs.getString('ws_uri') ?? 'wss://tryit.jssip.net:10443';
    _sipUri = prefs.getString('sip_uri') ?? 'hello_flutter@tryit.jssip.net';
    _displayName = prefs.getString('display_name') ?? 'Flutter SIP UA';
    _password = prefs.getString('password');
    prefs.commit();
    this.setState(() {});
  }

  _saveSettings() {
    prefs.setString('ws_uri', _wsUri);
    prefs.setString('sip_uri', _sipUri);
    prefs.setString('display_name', _displayName);
    prefs.setString('password', _password);
  }

  _handleRegisterState(state, data) {
    this.setState(() {
      _registerState = state;
    });
  }

  _handleSocketState(state, data) {
    this.setState(() {
      _registerState = state;
    });
  }

  _alert(context, alertFieldName) {
    showDialog<Null>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return new AlertDialog(
          title: new Text('$alertFieldName is empty'),
          content: new Text('Please enter $alertFieldName!'),
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

  _handleSave(context) {
    if (_wsUri == null) {
      return _alert(context, "WebSocket URL");
    } else if (_sipUri == null) {
      return _alert(context, "SIP URI");
    }
    bool addExtraHeaders = (_wsUri == 'wss://tryit.jssip.net:10443');
    helper.start(_wsUri, _sipUri, _password, _displayName,
        addExtraHeaders ? _wsExtraHeaders : null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text("SIP Account"),
        ),
        body: new Align(
            alignment: Alignment(0, 0),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Column(
                    children: <Widget>[
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(48.0, 18.0, 48.0, 18.0),
                        child: Center(
                            child: Text(
                          'Register Status: $_registerState',
                          style: TextStyle(fontSize: 18, color: Colors.black54),
                        )),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(48.0, 18.0, 48.0, 0),
                        child: Align(
                          child: Text('WebSocket:'),
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(48.0, 0.0, 48.0, 0),
                        child: TextField(
                          keyboardType: TextInputType.text,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            contentPadding: EdgeInsets.all(10.0),
                            border: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.black12)),
                            hintText: _wsUri,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _wsUri = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(46.0, 18.0, 48.0, 0),
                        child: Align(
                          child: Text('SIP URI:'),
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(48.0, 0.0, 48.0, 0),
                        child: TextField(
                          keyboardType: TextInputType.text,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            contentPadding: EdgeInsets.all(10.0),
                            border: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.black12)),
                            hintText: _sipUri,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _sipUri = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(46.0, 18.0, 48.0, 0),
                        child: Align(
                          child: Text('Password:'),
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(48.0, 0.0, 48.0, 0),
                        child: TextField(
                          keyboardType: TextInputType.text,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            contentPadding: EdgeInsets.all(10.0),
                            border: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.black12)),
                            hintText: _password ?? '[Empty]',
                          ),
                          onChanged: (value) {
                            setState(() {
                              _password = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(46.0, 18.0, 48.0, 0),
                        child: Align(
                          child: Text('Display Name:'),
                          alignment: Alignment.centerLeft,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(48.0, 0.0, 48.0, 0),
                        child: TextField(
                          keyboardType: TextInputType.text,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            contentPadding: EdgeInsets.all(10.0),
                            border: UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.black12)),
                            hintText: _displayName,
                          ),
                          onChanged: (value) {
                            setState(() {
                              _displayName = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(0.0, 18.0, 0.0, 0.0),
                      child: Container(
                        height: 48.0,
                        width: 160.0,
                        child: MaterialButton(
                          child: Text(
                            'Register',
                            style:
                                TextStyle(fontSize: 16.0, color: Colors.white),
                          ),
                          color: Colors.blue,
                          textColor: Colors.white,
                          onPressed: () => _handleSave(context),
                        ),
                      ))
                ])));
  }
}
