import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:provider/provider.dart';
import 'sip_ua_helper.dart';

class CallScreenWidget extends StatefulWidget {
  CallScreenWidget({Key key, this.title}) : super(key: key);
  final String title;

  @override
  _MyCallScreenWidget createState() => _MyCallScreenWidget();
}

class _MyCallScreenWidget extends State<CallScreenWidget> {
  RTCVideoRenderer _localRenderer = new RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = new RTCVideoRenderer();
  double _localVideoHeight;
  double _localVideoWidth;
  bool _haveRemoteVideo;
  EdgeInsetsGeometry _localVideoMargin;

  _MyCallScreenWidget();

  @override
  initState() {
    super.initState();
    _initRenders();
    _haveRemoteVideo = false;
  }

  @override
  deactivate() {
    super.deactivate();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _removeEventListeners();
  }

  _bindEventListeners() {
    Provider.of<SIPUAHelper>(context).on('stream', _handelStreams);
    Provider.of<SIPUAHelper>(context).on('ended', _handleEnded);
    Provider.of<SIPUAHelper>(context).on('failed', _handleFailed);
  }

  _removeEventListeners() {
    Provider.of<SIPUAHelper>(context).off('stream');
    Provider.of<SIPUAHelper>(context).off('ended');
    Provider.of<SIPUAHelper>(context).off('failed');
  }

  _handleEnded(e) {
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    new Timer(Duration(seconds: 1), () {
      Navigator.of(context).popUntil(ModalRoute.withName('/dialpad'));
    });
  }

  _handleFailed(e) {
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    new Timer(Duration(seconds: 1), () {
      Navigator.of(context).popUntil(ModalRoute.withName('/dialpad'));
    });
  }

  _handelStreams(event) {
    var stream = event['stream'];
    if (event['originator'] == 'local') {
      _localRenderer.srcObject = stream;
    }
    if (event['originator'] == 'remote') {
      _remoteRenderer.srcObject = stream;
      _haveRemoteVideo = true;
    }
    this.setState(() {
      _resizeLocalVideo();
    });
  }

  _initRenders() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  _resizeLocalVideo() {
    _localVideoMargin = _haveRemoteVideo
        ? EdgeInsets.only(top: 15, right: 15)
        : EdgeInsets.all(0);
    _localVideoWidth = _haveRemoteVideo
        ? MediaQuery.of(context).size.width / 4
        : MediaQuery.of(context).size.width;
    _localVideoHeight = _haveRemoteVideo
        ? MediaQuery.of(context).size.height / 4
        : MediaQuery.of(context).size.height;
  }

  _handleHangup(context) {
    Provider.of<SIPUAHelper>(context).hangup();
  }

  @override
  Widget build(BuildContext context) {
    _bindEventListeners();
    return Scaffold(
      appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
              "Calling [${Provider.of<SIPUAHelper>(context).sessionState}]")),
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
              alignment: Alignment.topRight,
              duration: Duration(milliseconds: 350),
              margin: _localVideoMargin,
            ),
            alignment: Alignment.topRight,
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: new FloatingActionButton(
        backgroundColor: Colors.red,
        onPressed: () => _handleHangup(context),
        tooltip: 'Hangup',
        child: new Icon(Icons.call_end),
      ),
    );
  }
}
