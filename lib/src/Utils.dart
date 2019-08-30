import 'dart:math' as DartMath;
import 'dart:core';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:random_string/random_string.dart';

import 'Grammar.dart';
import 'URI.dart';
import 'Constants.dart' as JsSIP_C;

test100(status_code){
  return status_code.contains(new RegExp(r'^100$'));
}

test1XX(status_code){
  return status_code.contains(new RegExp(r'^1[0-9]{2}$'));
}

test2XX(status_code){
  return status_code.contains(new RegExp(r'^2[0-9]{2}$'));
}

class Math {
  static final _random = DartMath.Random();
  static floor(num){
    return num.floor();
  }
  static randomDouble() => _random.nextDouble();
  static random() => _random.nextInt(0x7FFFFFFF);
  static pow(a, b){
    return DartMath.pow(a, b);
  }
}

str_utf8_length(string) => unescape(encodeURIComponent(string)).length;

// Used by 'hasMethods'.
isFunction(fn) {
  if (fn != null) {
    return (fn is Function);
  } else {
    return false;
  }
}

isString(str) {
  if (str != null) {
    return (str is String);
  } else {
    return false;
  }
}

isNaN(num) {
  return num.isNaN;
}

parseInt(str, radix) {
  return int.tryParse(str, radix: radix)?? null;
}

parseFloat(str) {
  return double.parse(str);
}

decodeURIComponent(str) {
  try {
    return Uri.decodeComponent(str);
  } catch (_) {
    return str;
  }
}

encodeURIComponent(str) {
  return Uri.encodeComponent(str);
}

unescape(str) {
  //TODO:  ??
  return str;
}

isDecimal(num) => !isNaN(num) && (parseFloat(num) == parseInt(num, 10));

isEmpty(value) {
  return (value == null ||
      value == '' ||
      value == null ||
      (value is List && value.length == 0) ||
      (value is num && isNaN(value)));
}

// Used by 'newTag'.
createRandomToken(size, {base = 32}) {
  return randomAlphaNumeric(size).toLowerCase();
}

newTag() => createRandomToken(10);

newUUID() => new Uuid().v4();

hostType(host) {
  if (host == null) {
    return null;
  } else {
    host = Grammar.parse(host, 'host');
    if (host != -1) {
      return host['host_type'];
    }
  }
}

/**
* Hex-escape a SIP URI user.
* Don't hex-escape ':' (%3A), '+' (%2B), '?' (%3F"), '/' (%2F).
*
* Used by 'normalizeTarget'.
*/
escapeUser(user) => encodeURIComponent(decodeURIComponent(user))
    .replaceAll(new RegExp(r'%3A', caseSensitive: false), ':')
    .replaceAll(new RegExp(r'%2B', caseSensitive: false), '+')
    .replaceAll(new RegExp(r'%3F', caseSensitive: false), '?')
    .replaceAll(new RegExp(r'%2F', caseSensitive: false), '/');

/**
* Normalize SIP URI.
* NOTE: It does not allow a SIP URI without username.
* Accepts 'sip', 'sips' and 'tel' URIs and convert them into 'sip'.
* Detects the domain part (if given) and properly hex-escapes the user portion.
* If the user portion has only 'tel' number symbols the user portion is clean of 'tel' visual separators.
*/
normalizeTarget(target, [domain]) {
  // If no target is given then raise an error.
  if (target == null) {
    return null;
    // If a URI instance is given then return it.
  } else if (target is URI) {
    return target;

    // If a string is given split it by '@':
    // - Last fragment is the desired domain.
    // - Otherwise append the given domain argument.
  } else if (target is String) {
    var target_array = target.split('@');
    var target_user;
    var target_domain;

    switch (target_array.length) {
      case 1:
        if (domain == null) {
          return null;
        }
        target_user = target;
        target_domain = domain;
        break;
      case 2:
        target_user = target_array[0];
        target_domain = target_array[1];
        break;
      default:
        target_user = target_array.sublist(0, target_array.length - 1).join('@');
        target_domain = target_array[target_array.length - 1];
    }

    // Remove the URI scheme (if present).
    target_user = target_user.replaceAll(
        new RegExp(r'^(sips?|tel):', caseSensitive: false), '');

    // Remove 'tel' visual separators if the user portion just contains 'tel' number symbols.
    if (target_user.contains(new RegExp(r'^[-.()]*\+?[0-9\-.()]+$'))) {
      target_user = target_user.replaceAll(new RegExp(r'[-.()]'), '');
    }

    // Build the complete SIP URI.
    target = JsSIP_C.SIP + ':' + escapeUser(target_user) + '@' + target_domain;

    // Finally parse the resulting URI.
    var uri = URI.parse(target);
    return uri;
  } else {
    return null;
  }
}

headerize(String string) {
  var exceptions = {
    'Call-Id': 'Call-ID',
    'Cseq': 'CSeq',
    'Www-Authenticate': 'WWW-Authenticate'
  };

  var name = string.toLowerCase().replaceAll('_', '-').split('-');
  var hname = '';
  var parts = name.length;
  var part;

  for (part = 0; part < parts; part++) {
    if (part != 0) {
      hname += '-';
    }
    hname += new String.fromCharCodes([name[part].codeUnitAt(0)]).toUpperCase() + name[part].substring(1);
  }
  if (exceptions[hname] != null) {
    hname = exceptions[hname];
  }

  return hname;
}

sipErrorCause(status_code) {
  var reason = JsSIP_C.Causes.SIP_FAILURE_CODE;
  JsSIP_C.SIP_ERROR_CAUSES.forEach((key, value) {
    if (value.contains(status_code)) {
      reason = key;
    }
  });
  return reason;
}

/**
* Generate a random Test-Net IP (https://tools.ietf.org/html/rfc5735)
*/
getRandomTestNetIP() {
  getOctet(from, to) {
    return num.parse(Math.floor(Math.random() * (to - from + 1)) + from);
  }

  return '192.0.2.' + getOctet(1, 254).toString();
}

calculateMD5(string) {
  return md5.convert(utf8.encode(string)).toString();
}

closeMediaStream(stream) {
  //TODO:  for flutter-webrtc.
}

cloneArray(array) {
  return (array != null && array is List)? array.sublist(0) : [];
}
