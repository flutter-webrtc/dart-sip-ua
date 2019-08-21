library sip_ua;

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
  var _parameters = {};
  var _headers = {};
  var user;
  var host;
  var port;

  URI(scheme, user, host, port, [parameters, headers]) {
    // Checks.
    if (host == null) {
      throw new AssertionError('missing or invalid "host" parameter');
    }

    // Initialize parameters.
    this._parameters = parameters ?? {};
    this._headers = headers ?? {};

    this.scheme = scheme ?? JsSIP_C.SIP;
    this.user = user;
    this.host = host;
    this.port = port;

    for (var param in parameters) {
      if (parameters.containsKey(param)) {
        this.setParam(param, parameters[param]);
      }
    }

    for (var header in headers) {
      if (headers.containsKey(header)) {
        this.setHeader(header, headers[header]);
      }
    }
  }

  setParam(key, value) {
    if (key) {
      this._parameters[key.toLowerCase()] =
          (value == null) ? null : value.toString();
    }
  }

  getParam(key) {
    if (key) {
      return this._parameters[key.toLowerCase()];
    }
  }

  hasParam(key) {
    if (key) {
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
    if (name) {
      return this._headers[Utils.headerize(name)];
    }
  }

  hasHeader(name) {
    if (name) {
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
    const headers = [];

    var uri = this.scheme + ':';

    if (this.user) {
      uri += Utils.escapeUser(this.user) + '@';
    }
    uri += this.host;
    if (this.port || this.port == 0) {
      uri += ':' + this.port.toString();
    }

    this._parameters.forEach((key, parameter) {
      if (this._parameters.containsKey(key)) {
        uri += ';' + parameter;
        if (this._parameters[key] != null) {
          uri += '=' + this._parameters[key].toString();
        }
      }
    });

    this._headers.forEach((key, header) {
      if (this._headers.containsKey(key)) {
        var header = this._headers[key];
        header.forEach((item) {
          headers.add(key + '=' + item.toString());
        });
      }
    });

    if (headers.length > 0) {
      uri += '?' + headers.join('&');
    }

    return uri;
  }

  toAor(show_port) {
    var aor = '?' + this.scheme + ':';

    if (this.user) {
      aor += Utils.escapeUser(this.user) + '@';
    }
    aor += this.host;
    if (show_port && (this.port || this.port == 0)) {
      aor += ':' + this.port.toString();
    }

    return aor;
  }
}
