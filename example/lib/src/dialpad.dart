import 'package:dart_sip_ua_example/src/test_credentials.dart';
import 'package:dart_sip_ua_example/src/theme_provider.dart';
import 'package:dart_sip_ua_example/src/user_state/sip_user_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:sip_ua/sip_ua.dart';

import 'widgets/action_button.dart';

class DialPadWidget extends StatefulWidget {
  final SIPUAHelper? _helper;

  DialPadWidget(this._helper, {Key? key}) : super(key: key);

  @override
  State<DialPadWidget> createState() => _MyDialPadWidget();
}

class _MyDialPadWidget extends State<DialPadWidget> implements SipUaHelperListener {
  String? _dest;
  SIPUAHelper? get helper => widget._helper;
  TextEditingController? _textController;
  late SipUserCubit currentUserCubit;
  final FocusNode _focusNode = FocusNode();

  final Logger _logger = Logger();

  String? receivedMsg;
  bool _audioMuted = false;
  bool _speakerOn = false;

  bool _hasAttemptedAutoRegister = false;

  @override
  initState() {
    super.initState();
    receivedMsg = "";
    _bindEventListeners();
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoRegister());
  }

  void _maybeAutoRegister() {
    if (!mounted || _hasAttemptedAutoRegister) return;
    final h = helper;
    if (h == null) return;
    if (h.registered) return;
    if (TestCredentials.username.isEmpty || TestCredentials.password.isEmpty) return;
    _hasAttemptedAutoRegister = true;
    context.read<SipUserCubit>().register(TestCredentials.sipUser);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _textController?.dispose();
    super.dispose();
  }

  void _loadSettings() {
    _dest = '';
    _textController = TextEditingController(text: _dest);
    _textController!.text = _dest ?? '';
    setState(() {});
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      final text = _textController!.text;
      if (text.isNotEmpty) {
        setState(() {
          _textController!.text = text.substring(0, text.length - 1);
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final character = event.character;
    if (character != null && character.isNotEmpty) {
      const validChars = '0123456789*#+';
      if (validChars.contains(character)) {
        setState(() {
          _textController!.text += character;
        });
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _handleMute() {
    final call = helper?.activeCall;
    if (call == null) return;
    _audioMuted = !_audioMuted;
    if (_audioMuted) {
      call.mute(true, false);
    } else {
      call.unmute(true, false);
    }
    setState(() {});
  }

  void _handleSpeaker() {
    final call = helper?.activeCall;
    if (call == null) return;
    _speakerOn = !_speakerOn;
    call.setSpeaker(_speakerOn);
    setState(() {});
  }

  void _bindEventListeners() {
    helper!.addSipUaHelperListener(this);
  }

  Future<Widget?> _handleCall(BuildContext context) async {
    final dest = _textController?.text;
    if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
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

    var mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': false,
    };

    final mediaStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    helper!.call(dest, voiceOnly: true, mediaStream: mediaStream);
    return null;
  }

  void _handleNum(String number) {
    setState(() {
      _textController!.text += number;
    });
  }

  List<Widget> _buildNumPad() {
    final labels = [
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
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = colorScheme.onSurface;

    final hasActiveCall = helper?.activeCall != null;
    return [
      const SizedBox(height: 8),
      TextField(
        keyboardType: TextInputType.text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, color: textColor),
        maxLines: 1,
        controller: _textController,
        decoration: InputDecoration(
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colorScheme.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colorScheme.outline),
          ),
        ),
      ),
      SizedBox(height: 20),
      Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: _buildNumPad(),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            ActionButton(
              icon: _audioMuted ? Icons.mic_off : Icons.mic,
              checked: _audioMuted,
              onPressed: hasActiveCall ? _handleMute : null,
            ),
            ActionButton(
              icon: Icons.call,
              fillColor: Colors.green,
              onPressed: () => _handleCall(context),
            ),
            ActionButton(
              icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
              checked: _speakerOn,
              onPressed: hasActiveCall ? _handleSpeaker : null,
            ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = colorScheme.onSurface;
    final iconColor = colorScheme.onSurface;
    bool isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    currentUserCubit = context.watch<SipUserCubit>();

    return Scaffold(
      appBar: AppBar(
        title: Text("CloudCall Demo"),
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
                  case 'theme':
                    final themeProvider = Provider.of<ThemeProvider>(context, listen: false); // get the provider, listen false is necessary cause is in a function

                    setState(() {
                      isDarkTheme = !isDarkTheme;
                    }); // change the variable

                    isDarkTheme // call the functions
                        ? themeProvider.setDarkmode()
                        : themeProvider.setLightMode();
                    break;
                  default:
                    break;
                }
              },
              icon: Icon(Icons.menu),
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem(
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.account_circle,
                            color: iconColor,
                          ),
                          SizedBox(width: 12),
                          Text('Account'),
                        ],
                      ),
                      value: 'account',
                    ),
                    PopupMenuItem(
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.info,
                            color: iconColor,
                          ),
                          SizedBox(width: 12),
                          Text(isDarkTheme ? 'Light Mode' : 'Dark Mode'),
                        ],
                      ),
                      value: 'theme',
                    )
                  ]),
        ],
      ),
      body: Focus(
        autofocus: true,
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent,
        child: ListView(
          padding: EdgeInsets.symmetric(horizontal: 12),
          children: <Widget>[
            SizedBox(height: 8),
            Center(
              child: Text(
                'Status: ${helper!.registerState.state?.name ?? ''}',
                style: TextStyle(fontSize: 18, color: textColor),
              ),
            ),
            SizedBox(height: 8),
            Center(
              child: Text(
                'Received Message: $receivedMsg',
                style: TextStyle(fontSize: 16, color: textColor),
              ),
            ),
            SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: _buildDialPad(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    setState(() {
      _logger.i("Registration state: ${state.state?.name}");
    });
  }

  @override
  void transportStateChanged(TransportState state) {}

  @override
  void callStateChanged(Call call, CallState callState) {
    switch (callState.state) {
      case CallStateEnum.CALL_INITIATION:
        Navigator.pushNamed(context, '/callscreen', arguments: call);
        break;
      case CallStateEnum.FAILED:
      case CallStateEnum.ENDED:
        setState(() {
          _audioMuted = false;
          _speakerOn = false;
        });
        if (callState.state == CallStateEnum.FAILED) {
          reRegisterWithCurrentUser();
        }
        break;
      case CallStateEnum.MUTED:
        setState(() {
          if (callState.audio == true) _audioMuted = true;
        });
        break;
      case CallStateEnum.UNMUTED:
        setState(() {
          if (callState.audio == true) _audioMuted = false;
        });
        break;
      default:
    }
  }

  void reRegisterWithCurrentUser() async {
    if (currentUserCubit.state == null) return;
    if (helper!.registered) await helper!.unregister();
    _logger.i("Re-registering");
    currentUserCubit.register(currentUserCubit.state!);
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

  @override
  void onNewReinvite(ReInvite event) {
    // TODO: implement onNewReinvite
  }
}
