import 'package:sip_ua/sip_ua.dart';

class SipUser {
  final String port;
  final String displayName;
  final String? wsUrl;
  final String? sipUri;
  final String password;
  final String host;
  final String authUser;
  final TransportType selectedTransport;
  final Map<String, String>? wsExtraHeaders;

  SipUser({
    required this.port,
    required this.displayName,
    required this.password,
    required this.authUser,
    required this.selectedTransport,
    required this.host,
    this.wsExtraHeaders,
    this.wsUrl,
    this.sipUri,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SipUser &&
        other.port == port &&
        other.displayName == displayName &&
        other.wsUrl == wsUrl &&
        other.sipUri == sipUri &&
        other.selectedTransport == selectedTransport &&
        other.wsExtraHeaders == wsExtraHeaders &&
        other.password == password &&
        other.authUser == authUser &&
        other.host == host;
  }

  @override
  int get hashCode {
    return Object.hashAll([port, displayName, wsUrl, sipUri, password, wsExtraHeaders, selectedTransport, authUser, host]);
  }
}
