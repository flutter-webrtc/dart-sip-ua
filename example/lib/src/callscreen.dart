import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:sip_ua/src/RTCSession.dart';
import 'package:sip_ua/src/NameAddrHeader.dart';
import 'package:sip_ua/src/event_manager/event_manager.dart';

import 'widgets/action_button.dart';
import 'sip_ua_helper.dart';

class CallScreenWidget extends StatefulWidget {
  final SIPUAHelper _helper;
  CallScreenWidget(this._helper, {Key key}) : super(key: key);
  @override
  _MyCallScreenWidget createState() => _MyCallScreenWidget();
}

class _MyCallScreenWidget extends State<CallScreenWidget> {
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  double _localVideoHeight;
  double _localVideoWidth;
  EdgeInsetsGeometry _localVideoMargin;
  MediaStream _localStream;
  MediaStream _remoteStream;
  String _direction;
  NameAddrHeader _local_identity;
  NameAddrHeader _remote_identity;
  bool _showNumPad = false;

  String _timeLabel = '00:00';
  Timer _timer;

  bool _audioMuted = false;
  bool _videoMuted = false;
  bool _speakerOn = false;
  bool _hold = false;
  String _holdOriginator;
  String _state = 'new';

  RTCSession get session => helper.session;

  SIPUAHelper get helper => widget._helper;

  bool get voiceonly =>
      (_localStream == null || _localStream.getVideoTracks().isEmpty) &&
      (_remoteStream == null || _remoteStream.getVideoTracks().isEmpty);

  String get remote_identity =>
      _remote_identity.display_name ?? _remote_identity.uri.user;

  @override
  initState() {
    super.initState();
    _initRenderers();
    _bindEventListeners();
    _startTimer();
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

  void _startTimer() {
    _timer = Timer.periodic(Duration(seconds: 1), (Timer timer) {
      Duration duration = Duration(seconds: timer.tick);
      if (mounted) {
        this.setState(() {
          _timeLabel = [duration.inMinutes, duration.inSeconds]
              .map((seg) => seg.remainder(60).toString().padLeft(2, '0'))
              .join(':');
        });
      } else {
        _timer.cancel();
      }
    });
  }

  void _initRenderers() async {
    if (_localRenderer != null) {
      await _localRenderer.initialize();
    }
    if (_remoteRenderer != null) {
      await _remoteRenderer.initialize();
    }
  }

  void _disposeRenderers() {
    if (_localRenderer != null) {
      _localRenderer.dispose();
      _localRenderer = null;
    }
    if (_remoteRenderer != null) {
      _remoteRenderer.dispose();
      _remoteRenderer = null;
    }
  }

  void _bindEventListeners() {
    helper.on(EventCallState(), _handleCalllState);
  }

  void _handleCalllState(EventCallState data) {
    if (data.state == 'hold' || data.state == 'unhold') {
      _hold = data.state == 'hold';
      _holdOriginator = data.originator;
      this.setState(() {});
      return;
    }

    if (data.state == 'muted') {
      if (data.audio) _audioMuted = true;
      if (data.video) _videoMuted = true;
      this.setState(() {});
      return;
    }

    if (data.state == 'unmuted') {
      if (data.audio) _audioMuted = false;
      if (data.video) _videoMuted = false;
      this.setState(() {});
      return;
    }

    if (data.state != 'stream') {
      _state = data.state;
    }

    switch (data.state) {
      case 'stream':
        _handelStreams(data);
        break;
      case 'progress':
      case 'connecting':
      case 'confirmed':
        break;
      case 'ended':
      case 'failed':
        _backToDialPad();
        break;
    }
  }

  void _removeEventListeners() {
    helper.remove(EventCallState(), _handleCalllState);
  }

  void _backToDialPad() {
    _timer.cancel();
    Timer(Duration(seconds: 2), () {
      Navigator.of(context).pop();
    });
  }

  void _handelStreams(EventCallState event) async {
    var stream = event.stream;
    if (event.originator == 'local') {
      if (_localRenderer != null) {
        _localRenderer.srcObject = stream;
      }
      _localStream = stream;
    }
    if (event.originator == 'remote') {
      if (_remoteRenderer != null) {
        _remoteRenderer.srcObject = stream;
      }
      _remoteStream = stream;
    }

    this.setState(() {
      _resizeLocalVideo();
    });
  }

  void _resizeLocalVideo() {
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

  void _handleHangup() {
    helper.hangup();
    _timer.cancel();
  }

  void _handleAccept() {
    helper.answer();
  }

  void _switchCamera() {
    if (_localStream != null) {
      _localStream.getVideoTracks()[0].switchCamera();
    }
  }

  void _muteAudio() {
    if (_audioMuted) {
      helper.unmute(true, false);
    } else {
      helper.mute(true, false);
    }
  }

  void _muteVideo() {
    if (_videoMuted) {
      helper.unmute(false, true);
    } else {
      helper.mute(false, true);
    }
  }

  void _handleHold() {
    if (_hold) {
      helper.unhold();
    } else {
      helper.hold();
    }
  }

  void _handleTransfer() {}

  void _handleKeyPad() {
    this.setState(() {
      //_showNumPad = !_showNumPad;
    });
    helper.sendDTMF('1');
  }

  void _toggleSpeaker() {
    if (_localStream != null) {
      _speakerOn = !_speakerOn;
      _localStream.getAudioTracks()[0].enableSpeakerphone(_speakerOn);
    }
  }

  Widget _buildActionButtons() {
    var hangupBtn = ActionButton(
      title: "hangup",
      onPressed: () => _handleHangup(),
      icon: Icons.call_end,
      fillColor: Colors.red,
    );

    var hangupBtnInactive = ActionButton(
      title: "hangup",
      onPressed: () {},
      icon: Icons.call_end,
      fillColor: Colors.grey,
    );

    var basicActions = <Widget>[];
    var advanceActions = <Widget>[];

    switch (_state) {
      case 'new':
      case 'connecting':
        if (_direction == 'INCOMING') {
          basicActions.add(ActionButton(
            title: "Accept",
            fillColor: Colors.green,
            icon: Icons.phone,
            onPressed: () => _handleAccept(),
          ));
          basicActions.add(hangupBtn);
        } else {
          basicActions.add(hangupBtn);
        }
        break;
      case 'accepted':
      case 'confirmed':
        {
          advanceActions.add(ActionButton(
            title: _audioMuted ? 'unmute' : 'mute',
            icon: _audioMuted ? Icons.mic_off : Icons.mic,
            checked: _audioMuted,
            onPressed: () => _muteAudio(),
          ));

          if (voiceonly) {
            advanceActions.add(ActionButton(
              title: "keypad",
              icon: Icons.dialpad,
              onPressed: () => _handleKeyPad(),
            ));
          } else {
            advanceActions.add(ActionButton(
              title: "switch camera",
              icon: Icons.switch_video,
              onPressed: () => _switchCamera(),
            ));
          }

          if (voiceonly) {
            advanceActions.add(ActionButton(
              title: _speakerOn ? 'speaker off' : 'speaker on',
              icon: _speakerOn ? Icons.volume_off : Icons.volume_up,
              checked: _speakerOn,
              onPressed: () => _toggleSpeaker(),
            ));
          } else {
            advanceActions.add(ActionButton(
              title: _videoMuted ? "camera on" : 'camera off',
              icon: _videoMuted ? Icons.videocam : Icons.videocam_off,
              checked: _videoMuted,
              onPressed: () => _muteVideo(),
            ));
          }

          basicActions.add(ActionButton(
            title: _hold ? 'unhold' : 'hold',
            icon: _hold ? Icons.play_arrow : Icons.pause,
            checked: _hold,
            onPressed: () => _handleHold(),
          ));

          basicActions.add(hangupBtn);

          basicActions.add(ActionButton(
            title: "transfer",
            icon: Icons.phone_forwarded,
            onPressed: () => _handleTransfer(),
          ));
        }
        break;
      case 'failed':
      case 'ended':
        basicActions.add(hangupBtnInactive);
        break;
      case 'progress':
        basicActions.add(hangupBtn);
        break;
      default:
        print('Other state => $_state');
        break;
    }

    var actionWidgets = <Widget>[];

    if (_showNumPad) {
    } else {
      if (advanceActions.isNotEmpty) {
        actionWidgets.add(Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: advanceActions)));
      }
    }

    actionWidgets.add(Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: basicActions)));

    return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.end,
        children: actionWidgets);
  }

  Widget _buildContent() {
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
          top: voiceonly ? 48 : 6,
          left: 0,
          right: 0,
          child: Center(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Center(
                  child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        (voiceonly ? 'VOICE CALL' : 'VIDEO CALL') +
                            (_hold
                                ? ' PAUSED BY ${this._holdOriginator.toUpperCase()}'
                                : ''),
                        style: TextStyle(fontSize: 24, color: Colors.black54),
                      ))),
              Center(
                  child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        '$remote_identity',
                        style: TextStyle(fontSize: 18, color: Colors.black54),
                      ))),
              Center(
                  child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(_timeLabel,
                          style:
                              TextStyle(fontSize: 14, color: Colors.black54))))
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
            padding: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 24.0),
            child: Container(width: 320, child: _buildActionButtons())));
  }
}
