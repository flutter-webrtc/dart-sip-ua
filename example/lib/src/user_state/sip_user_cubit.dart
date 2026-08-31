import 'package:bloc/bloc.dart';
import 'package:dart_sip_ua_example/src/user_state/sip_user.dart';
import 'package:sip_ua/sip_ua.dart';

class SipUserCubit extends Cubit<SipUser?> {
  final SIPUAHelper sipHelper;
  SipUserCubit({required this.sipHelper}) : super(null);

  void register(SipUser user) {
    UaSettings settings = UaSettings();

    // Sanitize the SIP URI: strip protocol prefixes from the host part
    // (e.g. "user@ws://sip.telnyx.com" → "user@sip.telnyx.com")
    String? cleanSipUri = user.sipUri;
    if (cleanSipUri != null && cleanSipUri.contains('@')) {
      final parts = cleanSipUri.split('@');
      String hostPart = parts.sublist(1).join('@');
      hostPart = hostPart.replaceFirst(RegExp(r'^(wss?|sips?|tcp|udp)://'), '');
      cleanSipUri = '${parts[0]}@$hostPart';
    }

    settings.port = user.port;
    settings.webSocketSettings.extraHeaders = user.wsExtraHeaders ?? {};
    settings.webSocketSettings.allowBadCertificate = true;
    settings.tcpSocketSettings.allowBadCertificate = true;
    settings.transportType = user.selectedTransport;
    settings.uri = cleanSipUri;
    settings.webSocketUrl = user.wsUrl;
    settings.host = cleanSipUri?.split('@').last;
    settings.authorizationUser = user.authUser;
    settings.password = user.password;
    settings.displayName = user.displayName;
    settings.userAgent = 'Dart SIP Client v1.0.0';
    settings.dtmfMode = DtmfMode.RFC2833;
    settings.contact_uri = cleanSipUri != null ? 'sip:$cleanSipUri' : null;

    emit(user);
    sipHelper.start(settings);
  }
}
