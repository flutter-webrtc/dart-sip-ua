import 'dart:core';

import 'constants.dart';
import 'uri.dart';

class ParsedData {
  ParsedData();

  String? host;
  int? port;
  String? host_type;
  int? cseq;
  String? method_str;
  String? reason_phrase;
  URI? uri;
  Map<String, List<String>> uri_headers = <String, List<String>>{};
  Map<String?, dynamic>? uri_params = <String?, dynamic>{};
  String? scheme;
  String? user;
  String? sip_version;
  int? status_code;
  bool? stale;
  String? algorithm;
  Map<String?, dynamic>? params = <String?, dynamic>{};
  List<Map<String, dynamic>> multi_header = <Map<String, dynamic>>[];
  late String call_id;
  String? display_name;
  String? nonce;
  String? from_tag;
  bool? early_only;
  String? opaque;
  String? password;
  List<String?> qop = <String?>[];
  String? protocol;
  String? realm;
  Map<String?, dynamic> auth_params = <String?, dynamic>{};
  int? cause;
  int? expires;
  String? refresher;
  int? rport;
  String? reason;
  String? retry_after;
  String? branch;
  String? maddr;
  int? ttl;
  Map<dynamic, dynamic>? received = <dynamic, dynamic>{};
  String? tag;
  String? to_tag;
  String? state;
  String? event;
  String? transport;
  String? text;
  String? uuid;

  SipMethod? get method => SipMethodHelper.fromString(method_str);
}
