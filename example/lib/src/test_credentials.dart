import 'package:dart_sip_ua_example/src/user_state/sip_user.dart';
import 'package:sip_ua/sip_ua.dart';

/// Single source for test SIP credentials (used by main.dart auto-register and Register screen).
/// Uses Edify staging (WSS). For other SIP-over-WebSocket providers that work with Flutter WebRTC:
/// - tryit.jssip.net (public demo; create account at jssip.net)
/// - Self-hosted: Asterisk/FreeSWITCH with WSS, or Jitsi SIP gateway
/// - Commercial: any SIP trunk with WebRTC/WSS support (e.g. Twilio Elastic SIP, etc.)
class TestCredentials {
  static SipUser get sipUser => _edify;

  // static String username = '';
  // static String password = '';

  static String username = '';
  static String password = '';

  /// Edify staging (WebSocket)
  static SipUser get _edify => SipUser(
        host: 'staging-sip-webrtc.edifycloud.net',
        wsUrl: 'wss://staging-sip-webrtc.edifycloud.net:19306/ws',
        selectedTransport: TransportType.WS,
        wsExtraHeaders: {},
        sipUri: '$username@staging-sip-webrtc.edifycloud.net',
        port: '19306',
        displayName: '+18573962130',
        password: password,
        authUser: username,
      );
}
