import 'constants.dart';
import 'logger.dart';
import 'utils.dart' as utils;

class Challenge {
  Challenge(this.algorithm, this.realm, this.nonce, this.opaque, this.stale,
      this.qop);
  factory Challenge.fromMap(Map<String, dynamic> map) {
    return Challenge(map['algorithm'], map['realm'], map['nonce'],
        map['opaque'], map['stale'], map['qop']);
  }
  String? algorithm;
  String? realm;
  String? nonce;
  String? opaque;
  bool? stale;
  dynamic qop; // String or List<dynamic>
}

class Credentials {
  Credentials(this.username, this.password, this.realm, this.ha1);
  factory Credentials.fromMap(Map<String, dynamic> map) {
    return Credentials(
        map['username'], map['password'], map['realm'], map['ha1']);
  }
  String? username;
  String? password;
  String? realm;
  String? ha1;
}

class DigestAuthentication {
  DigestAuthentication(this._credentials);

  late String _cnonce;
  int _nc = 0;
  String _ncHex = '00000000';
  String? _algorithm;
  String? _realm;
  String? _nonce;
  String? _opaque;
  bool? _stale;
  String? _qop;
  late SipMethod _method;
  dynamic _uri;
  String? _ha1;
  late String _response;
  final Credentials _credentials;
  String get response => _response;

  String? get(String parameter) {
    switch (parameter) {
      case 'realm':
        return _realm;

      case 'ha1':
        return _ha1;

      default:
        logger.e('get() | cannot get $parameter parameter');

        return null;
    }
  }

/**
* Performs Digest authentication given a SIP request and the challenge
* received in a response to that request.
* Returns true if auth was successfully generated, false otherwise.
*/
  bool authenticate(SipMethod method, Challenge challenge,
      [dynamic ruri, String? cnonce, String? body]) {
    _algorithm = challenge.algorithm;
    _realm = challenge.realm;
    _nonce = challenge.nonce;
    _opaque = challenge.opaque;
    _stale = challenge.stale;

    if (_algorithm != null) {
      if (_algorithm != 'MD5') {
        logger.e(
            'authenticate() | challenge with Digest algorithm different than "MD5", authentication aborted');

        return false;
      }
    } else {
      _algorithm = 'MD5';
    }

    if (_nonce == null) {
      logger.e(
          'authenticate() | challenge without Digest nonce, authentication aborted');

      return false;
    }

    if (_realm == null) {
      logger.e(
          'authenticate() | challenge without Digest realm, authentication aborted');

      return false;
    }

    // If no plain SIP password is provided.
    if (_credentials.password == null) {
      // If ha1 is not provided we cannot authenticate.
      if (_credentials.ha1 == null) {
        logger.e(
            'authenticate() | no plain SIP password nor ha1 provided, authentication aborted');

        return false;
      }

      // If the realm does not match the stored realm we cannot authenticate.
      if (_credentials.realm != _realm) {
        logger.e(
            'authenticate() | no plain SIP password, and stored "realm" does not match the given "realm", cannot authenticate [stored:"${_credentials.realm}", given:"$_realm"]');

        return false;
      }
    }

    // 'qop' can contain a list of values (Array). Let's choose just one.
    if (challenge.qop != null && challenge.qop.isNotEmpty) {
      if (challenge.qop.indexOf('auth-int') > -1) {
        _qop = 'auth-int';
      } else if (challenge.qop.indexOf('auth') > -1) {
        _qop = 'auth';
      } else {
        // Otherwise 'qop' is present but does not contain 'auth' or 'auth-int', so abort here.
        logger.e(
            'authenticate() | challenge without Digest qop different than "auth" or "auth-int", authentication aborted');

        return false;
      }
    } else {
      _qop = null;
    }

    // Fill other attributes.

    _method = method;
    _uri = ruri ?? '';
    _cnonce = cnonce ?? utils.createRandomToken(12);
    _nc += 1;
    String hex = _nc.toRadixString(16);

    _ncHex = '00000000'.substring(0, 8 - hex.length) + hex;

    // Nc-value = 8LHEX. Max value = 'FFFFFFFF'.
    if (_nc == 4294967296) {
      _nc = 1;
      _ncHex = '00000001';
    }

    // Calculate the Digest "response" value.

    // If we have plain SIP password then regenerate ha1.
    if (_credentials.password != null) {
      // HA1 = MD5(A1) = MD5(username:realm:password).
      _ha1 = utils.calculateMD5(
          '${_credentials.username}:$_realm:${_credentials.password}');
    }
    // Otherwise reuse the stored ha1.
    else {
      _ha1 = _credentials.ha1;
    }

    String a2;
    String ha2;

    if (_qop == 'auth') {
      // HA2 = MD5(A2) = MD5(method:digestURI).
      a2 = '${SipMethodHelper.getName(_method)}:$_uri';
      ha2 = utils.calculateMD5(a2);

      logger.d('authenticate() | using qop=auth [a2:$a2]');

      // Response = MD5(HA1:nonce:nonceCount:credentialsNonce:qop:HA2).
      _response =
          utils.calculateMD5('$_ha1:$_nonce:$_ncHex:$_cnonce:auth:$ha2');
    } else if (_qop == 'auth-int') {
      // HA2 = MD5(A2) = MD5(method:digestURI:MD5(entityBody)).
      a2 =
          '${SipMethodHelper.getName(_method)}:$_uri:${utils.calculateMD5(body ?? '')}';
      ha2 = utils.calculateMD5(a2);

      logger.d('authenticate() | using qop=auth-int [a2:$a2]');

      // Response = MD5(HA1:nonce:nonceCount:credentialsNonce:qop:HA2).
      _response =
          utils.calculateMD5('$_ha1:$_nonce:$_ncHex:$_cnonce:auth-int:$ha2');
    } else if (_qop == null) {
      // HA2 = MD5(A2) = MD5(method:digestURI).
      a2 = '${SipMethodHelper.getName(_method)}:$_uri';
      ha2 = utils.calculateMD5(a2);

      logger.d('authenticate() | using qop=null [a2:$a2]');

      // Response = MD5(HA1:nonce:HA2).
      _response = utils.calculateMD5('$_ha1:$_nonce:$ha2');
    }

    logger.d('authenticate() | response generated');

    return true;
  }

/**
* Return the Proxy-Authorization or WWW-Authorization header value.
*/
  @override
  String toString() {
    List<String> auth_params = <String>[];

    if (_response == null) {
      throw AssertionError(
          'response field does not exist, cannot generate Authorization header');
    }

    auth_params.add('algorithm=$_algorithm');
    auth_params.add('username="${_credentials.username}"');
    auth_params.add('realm="$_realm"');
    auth_params.add('nonce="$_nonce"');
    auth_params.add('uri="$_uri"');
    auth_params.add('response="$_response"');
    if (_opaque != null) {
      auth_params.add('opaque="$_opaque"');
    }
    if (_qop != null) {
      auth_params.add('qop=$_qop');
      auth_params.add('cnonce="$_cnonce"');
      auth_params.add('nc=$_ncHex');
    }
    if (_stale != null) {
      auth_params.add('stale=${_stale! ? 'true' : 'false'}');
    }
    return 'Digest ${auth_params.join(', ')}';
  }
}
