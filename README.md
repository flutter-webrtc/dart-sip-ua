# dart-sip-ua
A dart-lang version of the SIP UA stack, ported from [JsSIP](https://github.com/versatica/JsSIP).

## Overview
- Use pure [dart-lang](https://dart.dev)
- SIP over WebSocket (use real SIP in your flutter mobile, [desktop](https://flutter.dev/desktop), [web](https://flutter.dev/web) apps)
- Audio/video calls ([flutter-webrtc](https://github.com/cloudwebrtc/flutter-webrtc)) and instant messaging
- Support with standard SIP servers such as OpenSIPS, Kamailio, Asterisk and FreeSWITCH.

## Currently supported platforms
- [X] iOS
- [X] Android
- [X] Web
- [X] macOS
- [ ] Linux
- [ ] Windows
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

## Quickstart for Web platform
- [Install Flutter](https://flutter.dev/docs/get-started/install)
- Verify the install:
```
flutter doctor
```
- Run:
```
flutter channel beta
flutter upgrade
flutter config --enable-web
git clone https://github.com/cloudwebrtc/dart-sip-ua.git
cd dart-sip-ua/example
flutter create .
flutter pub get
flutter run -d chrome
```
Application should have loaded in Chrome.

Register with SIP server:

In the application, enter connexion settings by clicking the top-right hamburger menu, then click `Accounts`
- Click `Register`
  - If registration is ok, it should say `Status: Registered` at the top
  - If it fails to register, open Chrome Dev tools and looks for errors in the Javascript Console.

Calling:
- Once registered, click the top-left `Back Arrow` to return to keypad.
- Enter a phone number
- Click the green phone icone

## NOTE
Thanks to the original authors of [JsSIP](https://github.com/versatica/JsSIP) for providing the JS version, which makes it possible to port the [dart-lang](https://dart.dev).
- [José Luis Millán](https://github.com/jmillan)
- [Iñaki Baz Castillo](https://github.com/ibc)
- [Saúl Ibarra Corretgé](https://github.com/saghul)

## Sponsors
The first version was sponsored by Suretec Systems Ltd. T/A [SureVoIP](http://www.surevoip.co.uk).

## Contributing
The project is inseparable from the contributors of the community.
- [SureVoIP](https://github.com/SureVoIP) - Sponsor
- [CloudWebRTC](https://github.com/cloudwebrtc) - Original Author
- [Robert Sutton](https://github.com/rlsutton1) - Contributor
- [Gavin Henry](https://github.com/ghenry) - Contributor

## License
dart-sip-ua is released under the [MIT license](https://github.com/cloudwebrtc/dart-sip-ua/blob/master/LICENSE).
