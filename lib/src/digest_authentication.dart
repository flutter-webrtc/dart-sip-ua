import 'constants.dart';
import 'utils.dart' as Utils;
import 'logger.dart';

class Challenge {
  var algorithm;
  var realm;
  var nonce;
  var opaque;
  var stale;
  var qop;
  factory Challenge.fromMap(Map<String, dynamic> map) {
    return new Challenge(map['algorithm'], map['realm'], map['nonce'],
        map['opaque'], map['stale'], map['qop']);
  }
  Challenge(this.algorithm, this.realm, this.nonce, this.opaque, this.stale,
      this.qop);
}

class Credentials {
  var username;
  var password;
  var realm;
  var ha1;
  factory Credentials.fromMap(Map<String, dynamic> map) {
    return new Credentials(
        map['username'], map['password'], map['realm'], map['ha1']);
  }
  Credentials(this.username, this.password, this.realm, this.ha1);
}

class DigestAuthentication {
  var _cnonce;
  var _nc = 0;
  var _ncHex = '00000000';
  var _algorithm;
  var _realm;
  var _nonce;
  var _opaque;
  var _stale;
  var _qop;
  SipMethod _method;
  var _uri;
  var _ha1;
  var _response;
  Credentials _credentials;
  final logger = new Log();

  DigestAuthentication(this._credentials);

  get response => _response;

  get(parameter) {
    switch (parameter) {
      case 'realm':
        return this._realm;

      case 'ha1':
        return this._ha1;

      default:
        logger
            .error('get() | cannot get ' + parameter.toString() + ' parameter');

        return null;
    }
  }

/**
* Performs Digest authentication given a SIP request and the challenge
* received in a response to that request.
* Returns true if auth was successfully generated, false otherwise.
*/
  authenticate(SipMethod method, Challenge challenge, [ruri, cnonce, body]) {
    this._algorithm = challenge.algorithm;
    this._realm = challenge.realm;
    this._nonce = challenge.nonce;
    this._opaque = challenge.opaque;
    this._stale = challenge.stale;

    if (this._algorithm != null) {
      if (this._algorithm != 'MD5') {
        logger.error(
            'authenticate() | challenge with Digest algorithm different than "MD5", authentication aborted');

        return false;
      }
    } else {
      this._algorithm = 'MD5';
    }

    if (this._nonce == null) {
      logger.error(
          'authenticate() | challenge without Digest nonce, authentication aborted');

      return false;
    }

    if (this._realm == null) {
      logger.error(
          'authenticate() | challenge without Digest realm, authentication aborted');

      return false;
    }

    // If no plain SIP password is provided.
    if (this._credentials.password == null) {
      // If ha1 is not provided we cannot authenticate.
      if (this._credentials.ha1 == null) {
        logger.error(
            'authenticate() | no plain SIP password nor ha1 provided, authentication aborted');

        return false;
      }

      // If the realm does not match the stored realm we cannot authenticate.
      if (this._credentials.realm != this._realm) {
        logger.error(
            'authenticate() | no plain SIP password, and stored "realm" does not match the given "realm", cannot authenticate [stored:"${this._credentials.realm}", given:"${this._realm}"]');

        return false;
      }
    }

    // 'qop' can contain a list of values (Array). Let's choose just one.
    if (challenge.qop != null) {
      if (challenge.qop.indexOf('auth-int') > -1) {
        this._qop = 'auth-int';
      } else if (challenge.qop.indexOf('auth') > -1) {
        this._qop = 'auth';
      } else {
        // Otherwise 'qop' is present but does not contain 'auth' or 'auth-int', so abort here.
        logger.error(
            'authenticate() | challenge without Digest qop different than "auth" or "auth-int", authentication aborted');

        return false;
      }
    } else {
      this._qop = null;
    }

    // Fill other attributes.

    this._method = method;
    this._uri = ruri ?? '';
    this._cnonce = cnonce ?? Utils.createRandomToken(12);
    this._nc += 1;
    var hex = _nc.toRadixString(16);

    this._ncHex = '00000000'.substring(0, 8 - hex.length) + hex;

    // Nc-value = 8LHEX. Max value = 'FFFFFFFF'.
    if (this._nc == 4294967296) {
      this._nc = 1;
      this._ncHex = '00000001';
    }

    // Calculate the Digest "response" value.

    // If we have plain SIP password then regenerate ha1.
    if (this._credentials.password != null) {
      // HA1 = MD5(A1) = MD5(username:realm:password).
      this._ha1 = Utils.calculateMD5(
          '${this._credentials.username}:${this._realm}:${this._credentials.password}');
    }
    // Otherwise reuse the stored ha1.
    else {
      this._ha1 = this._credentials.ha1;
    }

    var a2;
    var ha2;

    if (this._qop == 'auth') {
      // HA2 = MD5(A2) = MD5(method:digestURI).
      a2 = '${SipMethodHelper.getName(this._method)}:${this._uri}';
      ha2 = Utils.calculateMD5(a2);

      logger.debug('authenticate() | using qop=auth [a2:${a2}]');

      // Response = MD5(HA1:nonce:nonceCount:credentialsNonce:qop:HA2).
      this._response = Utils.calculateMD5(
          '${this._ha1}:${this._nonce}:${this._ncHex}:${this._cnonce}:auth:${ha2}');
    } else if (this._qop == 'auth-int') {
      // HA2 = MD5(A2) = MD5(method:digestURI:MD5(entityBody)).
      a2 =
          '${SipMethodHelper.getName(this._method)}:${this._uri}:${Utils.calculateMD5(body != null ? body : '')}';
      ha2 = Utils.calculateMD5(a2);

      logger.debug('authenticate() | using qop=auth-int [a2:${a2}]');

      // Response = MD5(HA1:nonce:nonceCount:credentialsNonce:qop:HA2).
      this._response = Utils.calculateMD5(
          '${this._ha1}:${this._nonce}:${this._ncHex}:${this._cnonce}:auth-int:${ha2}');
    } else if (this._qop == null) {
      // HA2 = MD5(A2) = MD5(method:digestURI).
      a2 = '${SipMethodHelper.getName(this._method)}:${this._uri}';
      ha2 = Utils.calculateMD5(a2);

      logger.debug('authenticate() | using qop=null [a2:${a2}]');

      // Response = MD5(HA1:nonce:HA2).
      this._response = Utils.calculateMD5('${this._ha1}:${this._nonce}:${ha2}');
    }

    logger.debug('authenticate() | response generated');

    return true;
  }

/**
* Return the Proxy-Authorization or WWW-Authorization header value.
*/
  toString() {
    var auth_params = [];

    if (this._response == null) {
      throw new AssertionError(
          'response field does not exist, cannot generate Authorization header');
    }

    auth_params.add('algorithm=${this._algorithm}');
    auth_params.add('username="${this._credentials.username}"');
    auth_params.add('realm="${this._realm}"');
    auth_params.add('nonce="${this._nonce}"');
    auth_params.add('uri="${this._uri}"');
    auth_params.add('response="${this._response}"');
    if (this._opaque != null) {
      auth_params.add('opaque="${this._opaque}"');
    }
    if (this._qop != null) {
      auth_params.add('qop=${this._qop}');
      auth_params.add('cnonce="${this._cnonce}"');
      auth_params.add('nc=${this._ncHex}');
    }
    if (this._stale != null) {
      auth_params.add('stale=${this._stale ? 'true' : 'false'}');
    }
    return 'Digest ${auth_params.join(', ')}';
  }
}
