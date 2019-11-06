import 'dart:convert';

import 'grammar.dart';
import 'constants.dart' as DartSIP_C;
import 'utils.dart' as Utils;

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
    * Parse the given string and returns a DartSIP.URI instance or null if
    * it is an invalid URI.
    */
  static parse(uri) {
    try {
      return Grammar.parse(uri, 'SIP_URI');
    } catch (_) {
      return null;
    }
  }

  var _scheme;
  var _parameters;
  var _headers;
  var _user;
  var _host;
  var _port;

  URI(scheme, user, host, [port, parameters, headers]) {
    // Checks.
    if (host == null) {
      throw new AssertionError('missing or invalid "host" parameter');
    }

    // Initialize parameters.
    this._parameters = {};
    this._headers = {};
    this._scheme = scheme ?? DartSIP_C.SIP;
    this._user = user;
    this._host = host.toLowerCase();
    this._port = port;

    if (parameters != null) {
      parameters.forEach((param, value) {
        this.setParam(param, value);
      });
    }
    if (headers != null) {
      headers.forEach((header, value) {
        this.setHeader(header, value);
      });
    }
  }

  String get scheme => this._scheme;

  set scheme(String value) {
    this._scheme = value.toLowerCase();
  }

  String get user => this._user;

  set user(String value) {
    this._user = value;
  }

  String get host => this._host;

  set host(String value) {
    this._host = value.toLowerCase();
  }

  int get port => this._port;

  set port(int value) {
    this._port =
        value == 0 ? value : (value != null) ? Utils.parseInt(value, 10) : null;
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

  bool hasParam(key) {
    if (key != null) {
      return (this._parameters.containsKey(key.toLowerCase()) && true) || false;
    }
    return false;
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

    var uri = '${this._scheme}:';

    if (this.user != null) {
      uri += '${Utils.escapeUser(this.user)}@';
    }
    uri += this.host;
    if (this.port != null || this.port == 0) {
      uri += ':${this.port.toString()}';
    }

    this._parameters.forEach((key, parameter) {
      uri += ';${key}';
      if (this._parameters[key] != null) {
        uri += '=${this._parameters[key].toString()}';
      }
    });

    this._headers.forEach((key, header) {
      var hdrs = this._headers[key];
      hdrs.forEach((item) {
        headers.add('${Utils.headerize(key)}=${item.toString()}');
      });
    });

    if (headers.length > 0) {
      uri += '?${headers.join('&')}';
    }

    return uri;
  }

  toAor({show_port = false}) {
    var aor = '${this._scheme}:';

    if (this._user != null) {
      aor += '${Utils.escapeUser(this._user)}@';
    }
    aor += this._host;
    if (show_port && (this._port != null || this._port == 0)) {
      aor += ':${this._port}';
    }

    return aor;
  }
}
