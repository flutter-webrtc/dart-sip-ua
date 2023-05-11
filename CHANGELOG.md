# Changelog

--------------------------------------------
[0.5.8] - 2023.05.11
* Allow await on helper start call (#365)
* Adding params support for sendMessage (#366)
* Set intl version to the one used by flutter

[0.5.7] - 2023.05.11
* Add sendMessage to Call
* Bump version of intl

[0.5.6] - 2023.04.17

* Reverted version constraint on intl
* Bumped version of flutter_webrtc

[0.5.5] - 2023.03.08

* Bump version for intl & lints
* Update websocket_web_impl.dart (#345)
* fix(hangup): set cancel reason nullable (#346)
* Add sdp transformers (#350)
* Hold fix (#351)

[0.5.4] - 2023.02.20

* Bump version for flutter-webrtc
* Fixed error handling in _receiveInviteResponse #344
* Updated logger #342
* Websocket message queue using streams and Delay between messages #335
* Fixed bugs in message.dart & rtc_session.dart #332
* Allow setting ice_gathering_timeout option #330
* Add realm option to SIPUAHelper settings #331
* Code quality #326

[0.5.3] - 2022.10.19

* Bump version for flutter-webrtc
* Fix nullability in subscriber
* Fix flutter test
* Fix subscription parsing grammar
* Added ability to supply custom logger
* Added ability to get call statistics

[0.5.2] - 2022.08.05

* chore: Fix hold/unhold.

[0.5.1] - 2022.02.13

* chore: Fix compilation error for web.

[0.5.0] - 2022.02.08

* Null safety.
* Bump version for flutter-webrtc.

[0.4.0] - 2021.10.13

* Add extended header support (#235)
* Add iceGatheringTimeout for UaSettings.

[0.3.9] - 2021.09.27

* Upgrade flutter-webrtc to 0.6.8

[0.3.8] - 2021.09.26

* Fix ice delay.
* Don't run ready if session has been terminated (#226)
* Support IceRestart when IceStateDisconnected (#218)
* Add options to the hangup (#224)
* Adaptive when answering audio or video calls.

[0.3.7] - 2021.08.24

* Fix the issue that unified-plan's onTrack does not call back AudioTrack.
* Export PeerConnection for call.

[0.3.6] - 2021.08.24

* Support custom MediaStream for call/answer.
* Fix the exception caused by speaker operation in web mode.
* bump dependencies (#216)
* Fix the parameters with double quotes in the Authentication header,
    and the unknown parameters are saved to auth_params.
* updated crypto and uuid versions (#188)
* Update dependency sdp_transform to ^0.3.0
* Fixed mute audio for unified-plan
* Add remote_has_audio/video method for Call.
* Configuring via_transport.

[0.3.5] - 2021.02.03

* Upgrade flutter-webrtc to 0.5.8.
* Set sdpSemantics (plan-b or unfied-plan) to unfied-plan by default.
* Add correct transport param to contact uri. close #161, close #160.
* Let the user override the call options by extending SIPUAHelper (#170).

[0.3.4] - 2021.01.08

* fix bug.
* Check Content-Length loosely.
* [example] 🐛 makes sure speaker is off to match UI state

[0.3.3] - 2020.11.27

* Fix uri parse.
* Upgrade flutter_webrtc to 0.5.7.

[0.3.2] - 2020.11.11

* Added dtmf options to Call (#154)
* Fix bug for digest authentication.
* Fix rport parse (#144).
* Support RFC2833.
* Upgrade flutter_webrtc to 0.4.1.
* Fix incorrect register assert (#139).

[0.3.1] - 2020.10.18

* fix rport in Via parser.

[0.3.0] - 2020.10.18

* Upgrade flutter_webrtc to 0.4.0
* Get more pub points (#138)
* Fix Uri.parse
* Force use case sensitivity in Websocket Upgrade to be compatible with old SIP servers
* Expose Register Expires setting and if Register at all (Thanks ghenry@SureVoIP)
* extraContactUriParams now working and tested against OpenSIPS 3.1 that has RFC8599 support (Thanks ghenry@SureVoIP)

[0.2.4] - 2020.08.25

* Add missing key field `Sec-WebSocket-Protocol`.

[0.2.3] - 2020.08.25

* Add display_name for Call.
* Add WebSocketSettings.
* Fix the invalid extraHeaders in Registrator.
* Exposed local_identity for Call.
* Fixed Sec-WebSocket-Key keys are not 24 bytes.

[0.2.2] - 2020.07.16

* Refactor call API, move answer, hangup, hold etc methos to Call class.
* Add SIP message listener to listen the new incoming SIP text message.
* Expose ha1 in UaSettings.

[0.2.1] - 2020.06.12

* Add UnHandledResponse for registrationFailed.
* Add allowBadCertificate for UaSettings.
* Upgrade recase and logger.

[0.2.0] - 2020.05.27

* Fixed bug for incoming call.
* Just wait for 3 seconds for ice gathering.
* Upgrade flutter-webrtc version to 0.2.8.
* Prevent sharing of config between different UA instances.

[0.1.0] - 2019.12.13

* Initial release.
