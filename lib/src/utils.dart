import 'dart:math' as DartMath;
import 'dart:core';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:random_string/random_string.dart';

import 'grammar.dart';
import 'uri.dart';
import 'constants.dart' as DartSIP_C;

test100(statusCode) {
  return statusCode.contains(new RegExp(r'^100$'));
}

test1XX(statusCode) {
  return statusCode.contains(new RegExp(r'^1[0-9]{2}$'));
}

test2XX(statusCode) {
  return statusCode.contains(new RegExp(r'^2[0-9]{2}$'));
}

class Math {
  static final _random = DartMath.Random();
  static floor(num) {
    return num.floor();
  }

  static abs(num) {
    return num.abs();
  }

  static randomDouble() => _random.nextDouble();
  static random() => _random.nextInt(0x7FFFFFFF);
  static pow(a, b) {
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

isNaN(input) {
  return input.isNaN;
}

parseInt(input, radix) {
  return int.tryParse(input, radix: radix) ?? null;
}

parseFloat(input) {
  return double.tryParse(input) ?? null;
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
  //TODO:  ???
  return str;
}

isDecimal(input) =>
    input != null &&
    ((input is num && !isNaN(input)) ||
        (input is! num &&
            (parseFloat(input) != null || parseInt(input, 10) != null)));

isEmpty(value) {
  return (value == null ||
      value == '' ||
      value == null ||
      (value is List && value.isEmpty) ||
      (value is num && isNaN(value)));
}

// Used by 'newTag'.
String createRandomToken(size, {base = 32}) {
  return randomAlphaNumeric(size).toLowerCase();
}

String newTag() => createRandomToken(10);

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
    var targetArray = target.split('@');
    var targetUser;
    var targetDomain;

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
        new RegExp(r'^(sips?|tel):', caseSensitive: false), '');

    // Remove 'tel' visual separators if the user portion just contains 'tel' number symbols.
    if (targetUser.contains(new RegExp(r'^[-.()]*\+?[0-9\-.()]+$'))) {
      targetUser = targetUser.replaceAll(new RegExp(r'[-.()]'), '');
    }

    // Build the complete SIP URI.
    target = DartSIP_C.SIP + ':' + escapeUser(targetUser) + '@' + targetDomain;

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
    hname +=
        new String.fromCharCodes([name[part].codeUnitAt(0)]).toUpperCase() +
            name[part].substring(1);
  }
  if (exceptions[hname] != null) {
    hname = exceptions[hname];
  }

  return hname;
}

sipErrorCause(statusCode) {
  var reason = DartSIP_C.Causes.SIP_FAILURE_CODE;
  DartSIP_C.SIP_ERROR_CAUSES.forEach((key, value) {
    if (value.contains(statusCode)) {
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

cloneArray(array) {
  return (array != null && array is List) ? array.sublist(0) : [];
}
