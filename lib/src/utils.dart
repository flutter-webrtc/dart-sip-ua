import 'dart:convert';
import 'dart:core';
import 'dart:math' as DartMath;

import 'package:crypto/crypto.dart';
import 'package:random_string/random_string.dart';
import 'package:uuid/uuid.dart';

import 'constants.dart' as DartSIP_C;
import 'grammar.dart';
import 'uri.dart';

final JsonDecoder decoder = JsonDecoder();
final JsonEncoder encoder = JsonEncoder();

bool test100(String statusCode) {
  return statusCode.contains(RegExp(r'^100$'));
}

bool test1XX(String statusCode) {
  return statusCode.contains(RegExp(r'^1[0-9]{2}$'));
}

bool test2XX(String statusCode) {
  return statusCode.contains(RegExp(r'^2[0-9]{2}$'));
}

class Math {
  static final DartMath.Random _random = DartMath.Random();
  static num floor(num n) {
    return n.floor();
  }

  static num abs(num n) {
    return n.abs();
  }

  static double randomDouble() => _random.nextDouble();
  static int random() => _random.nextInt(0x7FFFFFFF);
  static num pow(num a, num b) {
    return DartMath.pow(a, b);
  }
}

int str_utf8_length(String string) =>
    unescape(encodeURIComponent(string)).length;

// Used by 'hasMethods'.
bool isFunction(dynamic fn) {
  if (fn != null) {
    return fn is Function;
  } else {
    return false;
  }
}

bool isString(dynamic str) {
  if (str != null) {
    return str is String;
  } else {
    return false;
  }
}

bool isNaN(dynamic input) {
  return input.isNaN;
}

int parseInt(String input, int radix) {
  return int.tryParse(input, radix: radix) ?? null;
}

double parseFloat(String input) {
  return double.tryParse(input) ?? null;
}

String decodeURIComponent(String str) {
  try {
    return Uri.decodeComponent(str);
  } catch (_) {
    return str;
  }
}

String encodeURIComponent(String str) {
  return Uri.encodeComponent(str);
}

String unescape(String str) {
  // TODO(cloudwebrtc):  ???
  return str;
}

bool isDecimal(dynamic input) =>
    input != null &&
    ((input is num && !isNaN(input)) ||
        (input is! num &&
            (parseFloat(input) != null || parseInt(input, 10) != null)));

bool isEmpty(dynamic value) {
  return value == null ||
      value == '' ||
      value == null ||
      (value is List && value.isEmpty) ||
      (value is num && isNaN(value));
}

// Used by 'newTag'.
String createRandomToken(int size, {int base = 32}) {
  return randomAlphaNumeric(size).toLowerCase();
}

String newTag() => createRandomToken(10);

String newUUID() => Uuid().v4();

dynamic hostType(String host) {
  if (host == null) {
    return null;
  } else {
    dynamic res = Grammar.parse(host, 'host');
    if (res != -1) {
      return res['host_type'];
    }
  }
}

/**
* Hex-escape a SIP URI user.
* Don't hex-escape ':' (%3A), '+' (%2B), '?' (%3F"), '/' (%2F).
*
* Used by 'normalizeTarget'.
*/
String escapeUser(String user) => encodeURIComponent(decodeURIComponent(user))
    .replaceAll(RegExp(r'%3A', caseSensitive: false), ':')
    .replaceAll(RegExp(r'%2B', caseSensitive: false), '+')
    .replaceAll(RegExp(r'%3F', caseSensitive: false), '?')
    .replaceAll(RegExp(r'%2F', caseSensitive: false), '/');

/**
* Normalize SIP URI.
* NOTE: It does not allow a SIP URI without username.
* Accepts 'sip', 'sips' and 'tel' URIs and convert them into 'sip'.
* Detects the domain part (if given) and properly hex-escapes the user portion.
* If the user portion has only 'tel' number symbols the user portion is clean of 'tel' visual separators.
*/
URI normalizeTarget(dynamic target, [String domain]) {
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
    List<String> targetArray = (target as String).split('@');
    String targetUser;
    String targetDomain;

    switch (targetArray.length) {
      case 1:
        if (domain == null) {
          return null;
        }
        targetUser = target;
        targetDomain = domain;
        break;
      case 2:
        targetUser = targetArray[0];
        targetDomain = targetArray[1];
        break;
      default:
        targetUser = targetArray.sublist(0, targetArray.length - 1).join('@');
        targetDomain = targetArray[targetArray.length - 1];
    }

    // Remove the URI scheme (if present).
    targetUser = targetUser.replaceAll(
        RegExp(r'^(sips?|tel):', caseSensitive: false), '');

    // Remove 'tel' visual separators if the user portion just contains 'tel' number symbols.
    if (targetUser.contains(RegExp(r'^[-.()]*\+?[0-9\-.()]+$'))) {
      targetUser = targetUser.replaceAll(RegExp(r'[-.()]'), '');
    }

    // Build the complete SIP URI.
    target = DartSIP_C.SIP + ':' + escapeUser(targetUser) + '@' + targetDomain;

    // Finally parse the resulting URI.
    return URI.parse(target);
  } else {
    return null;
  }
}

String headerize(String str) {
  Map<String, String> exceptions = <String, String>{
    'Call-Id': 'Call-ID',
    'Cseq': 'CSeq',
    'Www-Authenticate': 'WWW-Authenticate'
  };

  List<String> names = str.toLowerCase().replaceAll('_', '-').split('-');
  String hname = '';
  int parts = names.length;
  int part;

  for (part = 0; part < parts; part++) {
    if (part != 0) {
      hname += '-';
    }
    hname +=
        String.fromCharCodes(<int>[names[part].codeUnitAt(0)]).toUpperCase() +
            names[part].substring(1);
  }
  if (exceptions[hname] != null) {
    hname = exceptions[hname];
  }

  return hname;
}

String sipErrorCause(dynamic statusCode) {
  String reason = DartSIP_C.Causes.SIP_FAILURE_CODE;
  DartSIP_C.SIP_ERROR_CAUSES.forEach((String key, List<int> value) {
    if (value.contains(statusCode)) {
      reason = key;
    }
  });
  return reason;
}

String calculateMD5(String string) {
  return md5.convert(utf8.encode(string)).toString();
}

List<dynamic> cloneArray(List<dynamic> array) {
  return (array != null && array is List) ? array.sublist(0) : <dynamic>[];
}
