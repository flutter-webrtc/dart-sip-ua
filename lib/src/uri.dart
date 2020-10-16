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
  final JsonDecoder _decoder = JsonDecoder();
  final JsonEncoder _encoder = JsonEncoder();
  /**
    * Parse the given string and returns a DartSIP.URI instance or null if
    * it is an invalid URI.
    */
  static dynamic parse(String uri) {
    try {
      return Grammar.parse(uri, 'SIP_URI');
    } catch (_) {
      return null;
    }
  }

  String _scheme;
  Map<dynamic, dynamic> _parameters;
  Map<dynamic, dynamic> _headers;
  String _user;
  String _host;
  int _port;

  URI(String scheme, String user, String host,
      [int port,
      Map<dynamic, dynamic> parameters,
      Map<dynamic, dynamic> headers]) {
    // Checks.
    if (host == null) {
      throw AssertionError('missing or invalid "host" parameter');
    }

    // Initialize parameters.
    _parameters = parameters ?? {};
    _headers = headers ?? {};
    _scheme = scheme ?? DartSIP_C.SIP;
    _user = user;
    _host = host.toLowerCase();
    _port = port;

    if (parameters != null) {
      parameters.forEach((dynamic param, dynamic value) {
        setParam(param, value);
      });
    }
    if (headers != null) {
      headers.forEach((dynamic header, dynamic value) {
        setHeader(header, value);
      });
    }
  }

  String get scheme => _scheme;

  set scheme(String value) {
    _scheme = value.toLowerCase();
  }

  String get user => _user;

  set user(String value) {
    _user = value;
  }

  String get host => _host;

  set host(String value) {
    _host = value.toLowerCase();
  }

  int get port => _port;

  set port(int value) {
    _port = value == 0
        ? value
        : (value != null)
            ? Utils.parseInt(value.toString(), 10)
            : null;
  }

  void setParam(String key, dynamic value) {
    if (key != null) {
      _parameters[key.toLowerCase()] =
          (value == null) ? null : value.toString();
    }
  }

  dynamic getParam(String key) {
    if (key != null) {
      return _parameters[key.toLowerCase()];
    }
    return null;
  }

  bool hasParam(String key) {
    if (key != null) {
      return (_parameters.containsKey(key.toLowerCase()) && true) || false;
    }
    return false;
  }

  dynamic deleteParam(String parameter) {
    parameter = parameter.toLowerCase();
    if (_parameters.containsKey(parameter)) {
      dynamic value = _parameters[parameter];
      _parameters.remove(parameter);
      return value;
    }
  }

  void clearParams() {
    _parameters = {};
  }

  void setHeader(String name, dynamic value) {
    _headers[Utils.headerize(name)] =
        (value is List) ? value : <dynamic>[value];
  }

  dynamic getHeader(String name) {
    if (name != null) {
      return _headers[Utils.headerize(name)];
    }
    null;
  }

  bool hasHeader(String name) {
    if (name != null) {
      return (_headers.containsKey(Utils.headerize(name)) && true) || false;
    }
    return false;
  }

  dynamic deleteHeader(String header) {
    header = Utils.headerize(header);
    if (_headers.containsKey(header)) {
      dynamic value = _headers[header];
      _headers.remove(header);
      return value;
    }
    return null;
  }

  void clearHeaders() {
    _headers = {};
  }

  URI clone() {
    return URI(
        scheme,
        user,
        host,
        port,
        _decoder.convert(_encoder.convert(_parameters)),
        _decoder.convert(_encoder.convert(_headers)));
  }

  @override
  String toString() {
    var headers = [];

    var uri = '${_scheme}:';

    if (user != null) {
      uri += '${Utils.escapeUser(user)}@';
    }
    uri += host;
    if (port != null || port == 0) {
      uri += ':${port.toString()}';
    }

    _parameters.forEach((dynamic key, dynamic parameter) {
      uri += ';${key}';
      if (_parameters[key] != null) {
        uri += '=${_parameters[key].toString()}';
      }
    });

    _headers.forEach((key, header) {
      var hdrs = _headers[key];
      hdrs.forEach((item) {
        headers.add('${Utils.headerize(key)}=${item.toString()}');
      });
    });

    if (headers.length > 0) {
      uri += '?${headers.join('&')}';
    }

    return uri;
  }

  String toAor({bool show_port = false}) {
    var aor = '${_scheme}:';

    if (_user != null) {
      aor += '${Utils.escapeUser(_user)}@';
    }
    aor += _host;
    if (show_port && (_port != null || _port == 0)) {
      aor += ':${_port}';
    }

    return aor;
  }
}
