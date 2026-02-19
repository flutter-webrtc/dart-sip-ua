import 'package:dart_sip_ua_example/src/user_state/sip_user.dart';
import 'package:sip_ua/sip_ua.dart';

/// Single source for test SIP credentials (used by main.dart auto-register and Register screen).
/// Uses Edify staging (WSS). For other SIP-over-WebSocket providers that work with Flutter WebRTC:
/// - tryit.jssip.net (public demo; create account at jssip.net)
/// - Self-hosted: Asterisk/FreeSWITCH with WSS, or Jitsi SIP gateway
/// - Commercial: any SIP trunk with WebRTC/WSS support (e.g. Twilio Elastic SIP, etc.)
class TestCredentials {
  static SipUser get sipUser => _telnyx;

  static String username = '';
  static String password = '';

  static String telnyxUsername = '';
  static String telnyxPassword = '';

  /// Telnyx (WebSocket)
  static SipUser get _telnyx => SipUser(
        host: 'sip.telnyx.com',
        wsUrl: 'wss://sip.telnyx.com:7443',
        selectedTransport: TransportType.WS,
        wsExtraHeaders: {},
        sipUri: '$telnyxUsername@sip.telnyx.com',
        port: '7443',
        displayName: '',
        password: telnyxPassword,
        authUser: telnyxUsername,
      );
}
