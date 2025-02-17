import 'package:bloc/bloc.dart';
import 'package:dart_sip_ua_example/src/user_state/sip_user.dart';
import 'package:sip_ua/sip_ua.dart';

class SipUserCubit extends Cubit<SipUser?> {
  final SIPUAHelper sipHelper;
  SipUserCubit({required this.sipHelper}) : super(null);


  void register(SipUser user) {
    UaSettings settings = UaSettings();
    settings.port = user.port;
    settings.webSocketSettings.extraHeaders = user.wsExtraHeaders ?? {};
    settings.webSocketSettings.allowBadCertificate = true;
    //settings.webSocketSettings.userAgent = 'Dart/2.8 (dart:io) for OpenSIPS.';
    settings.tcpSocketSettings.allowBadCertificate = true;
    settings.transportType = user.selectedTransport;
    settings.uri = user.sipUri;
    settings.webSocketUrl = user.wsUrl;
    settings.host = user.sipUri?.split('@')[1];
    settings.authorizationUser = user.authUser;
    settings.password = user.password;
    settings.displayName = user.displayName;
    settings.userAgent = 'Dart SIP Client v1.0.0';
    settings.dtmfMode = DtmfMode.RFC2833;
    settings.contact_uri = 'sip:${user.sipUri}';

    emit(user);
    sipHelper.start(settings);
  }
}
