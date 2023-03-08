# dart-sip-ua

[![Financial Contributors on Open Collective](https://opencollective.com/flutter-webrtc/all/badge.svg?label=financial+contributors)](https://opencollective.com/flutter-webrtc) [![pub package](https://img.shields.io/pub/v/sip_ua.svg)](https://pub.dartlang.org/packages/sip_ua)  [![slack](https://img.shields.io/badge/join-us%20on%20slack-gray.svg?longCache=true&logo=slack&colorB=brightgreen)](https://join.slack.com/t/flutterwebrtc/shared_invite/zt-q83o7y1s-FExGLWEvtkPKM8ku_F8cEQ)
 
A dart-lang version of the SIP UA stack, ported from [JsSIP](https://github.com/versatica/JsSIP).

## Overview
- Use pure [dart-lang](https://dart.dev)
- SIP over WebSocket (use real SIP in your flutter mobile, [desktop](https://flutter.dev/desktop), [web](https://flutter.dev/web) apps)
- Audio/video calls ([flutter-webrtc](https://github.com/cloudwebrtc/flutter-webrtc)) and instant messaging
- Support with standard SIP servers such as OpenSIPS, Kamailio, Asterisk and FreeSWITCH.
- Support RFC2833 or INFO to send DTMF.

## Currently supported platforms
- [X] iOS
- [X] Android
- [X] Web
- [X] macOS
- [X] Windows
- [ ] Linux
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
- Kamailio
- or add your server example.

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

## License
dart-sip-ua is released under the [MIT license](https://github.com/cloudwebrtc/dart-sip-ua/blob/master/LICENSE).
