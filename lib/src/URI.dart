import 'dart:convert';

import 'Grammar.dart';
import 'Constants.dart' as JsSIP_C;
import 'Utils.dart' as Utils;

/**
 * -param {String} [scheme]
 * -param {String} [user]
 * -param {String} host
 * -param {String} [port]
 * -param {Object} [parameters]
 * -param {Object} [headers]
 *
 */
class URI {
  final JsonDecoder decoder = new JsonDecoder();
  final JsonEncoder encoder = new JsonEncoder();
  /**
    * Parse the given string and returns a JsSIP.URI instance or undefined if
    * it is an invalid URI.
    */
  static parse(uri) {
    uri = Grammar.parse(uri, 'SIP_URI');
    if (uri != -1) {
      return uri;
    } else {
      return null;
    }
  }

  var scheme;
  var _parameters;
  var _headers;
  var user;
  var host;
  int port;

  URI(scheme, user, host, port, [parameters, headers]) {
    // Checks.
    if (host == null) {
      throw new AssertionError('missing or invalid "host" parameter');
    }

    // Initialize parameters.
    this._parameters = {};
    this._headers =  {};
    this.scheme = scheme ?? JsSIP_C.SIP;
    this.user = user;
    this.host = host.toLowerCase();
    this.port = port;

    parameters.forEach((param, value) {
      this.setParam(param, value);
    });

    headers.forEach((header, value){
      this.setHeader(header, value);
    });
  }

  setParam(key, value) {
    if (key != null) {
      this._parameters[key.toLowerCase()] =
          (value == null) ? null : value.toString();
    }
  }

  getParam(key) {
    if (key != null) {
      return this._parameters[key.toLowerCase()];
    }
  }

  hasParam(key) {
    if (key != null) {
      return (this._parameters.containsKey(key.toLowerCase()) && true) || false;
    }
  }

  deleteParam(parameter) {
    parameter = parameter.toLowerCase();
    if (this._parameters.containsKey(parameter)) {
      var value = this._parameters[parameter];
      this._parameters.remove(parameter);
      return value;
    }
  }

  clearParams() {
    this._parameters = {};
  }

  setHeader(name, value) {
    this._headers[Utils.headerize(name)] = (value is List) ? value : [value];
  }

  getHeader(name) {
    if (name != null) {
      return this._headers[Utils.headerize(name)];
    }
  }

  hasHeader(name) {
    if (name != null) {
      return (this._headers.containsKey(Utils.headerize(name)) && true) ||
          false;
    }
  }

  deleteHeader(header) {
    header = Utils.headerize(header);
    if (this._headers.containsKey(header)) {
      var value = this._headers[header];
      this._headers.remove(header);
      return value;
    }
  }

  clearHeaders() {
    this._headers = {};
  }

  clone() {
    return new URI(
        this.scheme,
        this.user,
        this.host,
        this.port,
        decoder.convert(encoder.convert(this._parameters)),
        decoder.convert(encoder.convert(this._headers)));
  }

  toString() {
    var headers = [];

    var uri = this.scheme + ':';

    if (this.user != null) {
      uri += Utils.escapeUser(this.user) + '@';
    }
    uri += this.host;
    if (this.port != null || this.port == 0) {
      uri += ':' + this.port.toString();
    }

    this._parameters.forEach((key, parameter) {
      uri += ';' + key;
      if (this._parameters[key] != null) {
        uri += '=' + this._parameters[key].toString();
      }
    });

    this._headers.forEach((key, header) {
      var hdrs = this._headers[key];
      hdrs.forEach((item) {
        headers.add(Utils.headerize(key) + '=' + item.toString());
      });
    });

    if (headers.length > 0) {
      uri += '?' + headers.join('&');
    }

    return uri;
  }

  toAor({show_port}) {
    var aor = this.scheme + ':';

    if (this.user != null) {
      aor += Utils.escapeUser(this.user) + '@';
    }
    aor += this.host;
    if ((show_port != null && show_port == true) &&
        (this.port != null || this.port == 0)) {
      aor += ':' + this.port.toString();
    }

    return aor;
  }
}
