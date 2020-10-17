import 'dart:core';

import 'constants.dart';
import 'uri.dart';

class ParsedData {
  ParsedData();

  var host;
  var port;
  var host_type;
  var value;
  String method_str;
  var reason_phrase;
  URI uri;
  var uri_headers;
  var uri_params;
  var scheme;
  var user;
  var sip_version;
  var status_code;
  var stale;
  var algorithm;
  var params = {};
  var multi_header;
  var call_id;
  var display_name;
  var nonce;
  var from_tag;
  var early_only;
  var opaque;
  var password;
  var qop;
  var protocol;
  var realm;
  var auth_params;
  var cause;
  var expires;
  var refresher;
  var rport;
  var reason;
  var retry_after;
  var branch;
  var maddr;
  var ttl;
  var received;
  var tag;
  var to_tag;
  var state;
  var event;
  var transport;
  var text;
  var uuid;

  SipMethod get method => SipMethodHelper.fromString(method_str);
}
