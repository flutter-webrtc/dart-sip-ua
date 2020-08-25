# Changelog

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
