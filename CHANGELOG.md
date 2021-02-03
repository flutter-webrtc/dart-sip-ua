# Changelog

--------------------------------------------
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
