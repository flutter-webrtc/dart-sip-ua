import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'sip_ua_helper.dart';

class CallScreenWidget extends StatefulWidget {
  SIPUAHelper _helper;
  CallScreenWidget(this._helper, {Key key}) : super(key: key);
  @override
  _MyCallScreenWidget createState() => _MyCallScreenWidget();
}

class _MyCallScreenWidget extends State<CallScreenWidget> {
  RTCVideoRenderer _localRenderer = new RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = new RTCVideoRenderer();
  double _localVideoHeight;
  double _localVideoWidth;
  EdgeInsetsGeometry _localVideoMargin;
  var _localStream;
  var _remoteStream;
  var _direction;
  bool _muted = false;

  get session => helper.session;

  get helper => widget._helper;

  @override
  initState() {
    super.initState();
    _initRenderers();
    _bindEventListeners();
    _direction = session.direction.toUpperCase();
  }

  @override
  deactivate() {
    super.deactivate();
    _removeEventListeners();
    _disposeRenderers();
  }

  _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  _disposeRenderers() {
    if (_localRenderer != null) {
      _localRenderer.dispose();
      _localRenderer = null;
    }
    if (_remoteRenderer != null) {
      _remoteRenderer.dispose();
      _remoteRenderer = null;
    }
  }

  _bindEventListeners() {
    helper.on('callState', _handleCalllState);
  }

  _handleCalllState(state, data) {
    switch (state) {
      case 'stream':
        _handelStreams(data);
        break;
      case 'ended':
      case 'failed':
        _backToDialPad();
        break;
    }
    this.setState(() {});
  }

  _removeEventListeners() {
    helper.off('callState');
  }

  _backToDialPad() {
    new Timer(Duration(seconds: 2), () {
      Navigator.of(context).popUntil(ModalRoute.withName('/dialpad'));
    });
  }

  _handelStreams(event) async {
    var stream = event['stream'];
    if (event['originator'] == 'local') {
      _localRenderer.srcObject = stream;
      _localStream = stream;
    }
    if (event['originator'] == 'remote') {
      _remoteRenderer.srcObject = stream;
      _remoteStream = stream;
    }

    this.setState(() {
      _resizeLocalVideo();
    });
  }

  _resizeLocalVideo() {
    _localVideoMargin = _remoteStream != null
        ? EdgeInsets.only(top: 15, right: 15)
        : EdgeInsets.all(0);
    _localVideoWidth = _remoteStream != null
        ? MediaQuery.of(context).size.width / 4
        : MediaQuery.of(context).size.width;
    _localVideoHeight = _remoteStream != null
        ? MediaQuery.of(context).size.height / 4
        : MediaQuery.of(context).size.height;
  }

  _handleHangup() {
    helper.hangup();
  }

  _handleAccept() {
    helper.answer();
  }

  _switchCamera() {
    if (_localStream != null) {
      _localStream.getVideoTracks()[0].switchCamera();
    }
  }

  _muteMic() {
    if (_localStream != null) {
      this.setState(() {
        _muted = !_muted;
      });
      _localStream.getAudioTracks()[0].setMicrophoneMute(_muted);
    }
  }

  _buildActionButtons() {
    var buttons = <Widget>[];
    var showAcceptBtn = (_direction == 'INCOMING' &&
        helper.sessionState != 'confirmed' &&
        helper.sessionState != 'ended');

    var confirmed = helper.sessionState == 'confirmed';

    if (showAcceptBtn) {
      buttons.add(FloatingActionButton(
        heroTag: "accept",
        backgroundColor: Colors.green,
        child: const Icon(Icons.phone),
        tooltip: 'Accept',
        onPressed: () => _handleAccept(),
      ));
    }

    if (confirmed) {
      buttons.add(FloatingActionButton(
        heroTag: "switch_camera",
        child: const Icon(Icons.switch_camera),
        onPressed: () => _switchCamera(),
      ));
    }

    buttons.add(FloatingActionButton(
      heroTag: "hangup",
      onPressed: () => _handleHangup(),
      tooltip: 'Hangup',
      child: new Icon(Icons.call_end),
      backgroundColor: Colors.red,
    ));

    if (confirmed) {
      buttons.add(FloatingActionButton(
        heroTag: "mute_mic",
        child: new Icon(_muted ? Icons.mic_off : Icons.mic),
        onPressed: () => _muteMic(),
      ));
    }

    return buttons;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text("[$_direction] ${helper.sessionState}")),
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
                duration: Duration(milliseconds: 300),
                margin: _localVideoMargin,
              ),
              alignment: Alignment.topRight,
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: SizedBox(
            width: 200.0,
            child: new Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _buildActionButtons())));
  }
}
