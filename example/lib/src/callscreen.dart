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

enum CallType { kCallTypeVoice, kCallTypeVideo }

class _MyCallScreenWidget extends State<CallScreenWidget> {
  RTCVideoRenderer _localRenderer = new RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = new RTCVideoRenderer();
  double _localVideoHeight;
  double _localVideoWidth;
  EdgeInsetsGeometry _localVideoMargin;
  var _localStream;
  var _remoteStream;
  var _direction;
  var _local_identity;
  var _remote_identity;
  bool _showDialPad = false;
  var _label;
  var _timeLabel;

  bool _muted = false;
  bool _hold = false;
  CallType _type = CallType.kCallTypeVideo;
  var _state = 'new';

  get session => helper.session;

  get helper => widget._helper;

  get voiceonly =>
      (_localStream == null || _localStream.getVideoTracks().length == 0) &&
      (_remoteStream == null || _remoteStream.getVideoTracks().length == 0);

  @override
  initState() {
    super.initState();
    _initRenderers();
    _bindEventListeners();
    _direction = session.direction.toUpperCase();
    _local_identity = session.local_identity;
    _remote_identity = session.remote_identity;
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
    if (state != 'stream') {
      _state = state;
    }

    switch (state) {
      case 'stream':
        _handelStreams(data);
        break;
      case 'progress':
        break;
      case 'confirmed':
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

  _handleHold() {}

  _buildActionButtons() {
    var hangupBtn = FloatingActionButton(
      heroTag: "hangup",
      onPressed: () => _handleHangup(),
      tooltip: 'Hangup',
      child: new Icon(Icons.call_end),
      backgroundColor: Colors.red,
    );

    var hangupBtnInactive = FloatingActionButton(
      heroTag: "hangup",
      onPressed: () => _handleHangup(),
      tooltip: 'Hangup',
      child: new Icon(Icons.call_end),
      backgroundColor: Colors.grey,
    );

    var basicActions = <Widget>[];
    var advanceActions = <Widget>[];

    switch (_state) {
      case 'new':
        if (_direction == 'INCOMING') {
          basicActions.add(FloatingActionButton(
            heroTag: "accept",
            backgroundColor: Colors.green,
            child: const Icon(Icons.phone),
            tooltip: 'Accept',
            onPressed: () => _handleAccept(),
          ));
          basicActions.add(hangupBtn);
        } else {
          basicActions.add(hangupBtn);
        }
        break;
      case 'confirmed':
        {
          advanceActions.add(FloatingActionButton(
            heroTag: "mute_mic",
            child: new Icon(_muted ? Icons.mic_off : Icons.mic),
            onPressed: () => _muteMic(),
          ));

          if(voiceonly) {
              advanceActions.add(FloatingActionButton(
                heroTag: "keypad",
                child: new Icon(Icons.dialpad),
                onPressed: () => _handleHold(),
              ));
          } else {
              advanceActions.add(FloatingActionButton(
                heroTag: "switch_camera",
                child: const Icon(Icons.switch_camera),
                onPressed: () => _switchCamera(),
              ));
          }

          advanceActions.add(FloatingActionButton(
            heroTag: "speaker",
            child: new Icon(Icons.volume_up),
            onPressed: () => _handleHold(),
          ));

          basicActions.add(FloatingActionButton(
            heroTag: "hold",
            child: new Icon(_hold ? Icons.pause : Icons.pause),
            onPressed: () => _handleHold(),
          ));

          basicActions.add(hangupBtn);

          basicActions.add(FloatingActionButton(
            heroTag: "transfer",
            child: new Icon(Icons.phone_forwarded),
            onPressed: () => _handleHold(),
          ));
        }
        break;
      case 'failed':
      case 'ended':
        basicActions.add(hangupBtnInactive);
        break;
      case 'progress':
      case 'connecting':
        basicActions.add(hangupBtn);
        break;
    }

    var actionWidgets = <Widget>[];

    if (advanceActions.length > 0) {
      actionWidgets.add(Padding(
          padding: const EdgeInsets.all(3),
          child: new Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: advanceActions)));
    }

    actionWidgets.add(Padding(
        padding: const EdgeInsets.all(3),
        child: new Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: basicActions)));

    return new Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: actionWidgets);
  }

  _buildContent() {
    var stackWidgets = <Widget>[];

    if (!voiceonly && _remoteStream != null) {
      stackWidgets.add(Center(
        child: RTCVideoView(_remoteRenderer),
      ));
    }

    if (!voiceonly && _localStream != null) {
      stackWidgets.add(Container(
        child: AnimatedContainer(
          child: RTCVideoView(_localRenderer),
          height: _localVideoHeight,
          width: _localVideoWidth,
          alignment: Alignment.topRight,
          duration: Duration(milliseconds: 300),
          margin: _localVideoMargin,
        ),
        alignment: Alignment.topRight,
      ));
    }

    return Stack(
      children: <Widget>[
        ...stackWidgets,
        Positioned(
          top: voiceonly? 180 : 6,
          left: 0,
          right: 0,
          child: Center(
              child: new Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Center(
                  child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        voiceonly? 'VOICE CALL' : 'VIDEO CALL',
                        style: TextStyle(fontSize: 24, color: Colors.black54),
                      ))),
              Center(
                  child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        '${_remote_identity.toString()}',
                        style: TextStyle(fontSize: 18, color: Colors.black54),
                      ))),
              Center(
                  child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text('00:00',
                          style:
                              TextStyle(fontSize: 14, color: Colors.black54)))),
            ],
          )),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text('[$_direction] ${_state}')),
        body: Container(
          child: _buildContent(),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: Padding(
          padding: const EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 36.0),
          child: new Container(
              height: 128, width: 300, child: _buildActionButtons()),
        ));
  }
}
