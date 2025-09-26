# dart-sip-ua

[![Financial Contributors on Open Collective](https://opencollective.com/flutter-webrtc/all/badge.svg?label=financial+contributors)](https://opencollective.com/flutter-webrtc) [![pub package](https://img.shields.io/pub/v/sip_ua.svg)](https://pub.dev/packages/sip_ua)  [![slack](https://img.shields.io/badge/join-us%20on%20slack-gray.svg?longCache=true&logo=slack&colorB=brightgreen)](https://join.slack.com/t/flutterwebrtc/shared_invite/zt-q83o7y1s-FExGLWEvtkPKM8ku_F8cEQ)
 
A dart-lang version of the SIP UA stack, ported from [JsSIP](https://github.com/versatica/JsSIP).

## Overview
- Use pure [dart-lang](https://dart.dev)
- SIP over WebSocket && TCP (use real SIP in your flutter mobile, [desktop](https://flutter.dev/desktop), [web](https://flutter.dev/web) apps)
- Audio/video calls ([flutter-webrtc](https://github.com/cloudwebrtc/flutter-webrtc)) and instant messaging
- Support with standard SIP servers such as OpenSIPS, Kamailio, Asterisk, 3CX and FreeSWITCH.
- Support RFC2833 or INFO to send DTMF.

## Currently supported platforms
- [X] iOS
- [X] Android
- [X] Web
- [X] macOS
- [X] Windows
- [X] Linux
- [ ] Fuchsia

## Install

### Android

- Proguard rules:

```
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

-keep class com.cloudwebrtc.webrtc.** {*;}
-keep class org.webrtc.** {*;}
```

## Quickstart

Run example:

- [dart-sip-ua-example](https://github.com/flutter-webrtc/dart-sip-ua/blob/master/example/README.md)
- or add your example.

Register with SIP server:

- [Asterisk](https://github.com/flutter-webrtc/dockers/tree/main/asterisk)
- FreeSWITCH
- OpenSIPS
- 3CX
- Kamailio
- or add your server example.

## FAQ's OR ISSUES
<details>

<summary>expand</summary>

## Server not configured for DTLS/SRTP

WEBRTC_SET_REMOTE_DESCRIPTION_ERROR: Failed to set remote offer sdp: Called with SDP without DTLS fingerprint.

Your server is not sending a DTLS fingerprint inside the SDP when inviting the sip_ua client to start a call.

WebRTC uses encryption by Default, all WebRTC communications (audio, video, and data) are encrypted using DTLS and SRTP, ensuring secure communication. Your PBX must be configured to use DTLS/SRTP when calling sip_ua.


## Why isn't there a UDP connection option?

This package uses a WS or TCP connection for the signalling processs to initiate or terminate a session (sip messages).
Once the session is connected WebRTC transmits the actual media (audio/video) over UDP.

If anyone actually still wants to use UDP for the signalling process, feel free to submit a PR with the large amount of work needed to set it up, packet order checking, error checking, reliability timeouts, flow control, security etc etc.

## SIP/2.0 488 Not acceptable here

The codecs on your PBX server don't match the codecs used by WebRTC

- **opus** (payload type 111, 48kHz, 2 channels)
- **red** (payload type 63, 48kHz, 2 channels)
- **G722** (payload type 9, 8kHz, 1 channel)
- **ILBC** (payload type 102, 8kHz, 1 channel)
- **PCMU** (payload type 0, 8kHz, 1 channel)
- **PCMA** (payload type 8, 8kHz, 1 channel)
- **CN** (payload type 13, 8kHz, 1 channel)
- **telephone-event** (payload type 110, 48kHz, 1 channel for wideband, 8000Hz, 1 channel for narrowband)

</details>


## NOTE
Thanks to the original authors of [JsSIP](https://github.com/versatica/JsSIP) for providing the JS version, which makes it possible to port the [dart-lang](https://dart.dev).
- [José Luis Millán](https://github.com/jmillan)
- [Iñaki Baz Castillo](https://github.com/ibc)
- [Saúl Ibarra Corretgé](https://github.com/saghul)

## Sponsors
The first version was sponsored by Suretec Systems Ltd. T/A [SureVoIP](https://www.surevoip.co.uk).

## Contributing
The project is inseparable from the contributors of the community.
- [SureVoIP](https://github.com/SureVoIP) - Sponsor
- [CloudWebRTC](https://github.com/cloudwebrtc) - Original Author
- [Robert Sutton](https://github.com/rlsutton1) - Contributor
- [Gavin Henry](https://github.com/ghenry) - Contributor
- [Perondas](https://github.com/Perondas) - Contributor
- [Mikael Wills](https://github.com/mikaelwills) - Contributor

## License
dart-sip-ua is released under the [MIT license](https://github.com/cloudwebrtc/dart-sip-ua/blob/master/LICENSE).
