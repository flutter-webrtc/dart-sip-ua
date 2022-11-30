import 'constants.dart' as DartSIP_C;
import 'grammar.dart';
import 'utils.dart' as utils;
import 'utils.dart';

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
  URI(String? scheme, this.user, String? host,
      [int? port,
      Map<dynamic, dynamic>? parameters,
      Map<dynamic, dynamic>? headers]) {
    // Checks.
    if (host == null) {
      throw AssertionError('missing or invalid "host" parameter');
    }
    _scheme = scheme ?? DartSIP_C.SIP;
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

  String? user;
  late String _scheme;
  Map<dynamic, dynamic> _parameters = <dynamic, dynamic>{};
  Map<dynamic, dynamic> _headers = <dynamic, dynamic>{};
  late String _host;
  int? _port;
  String get scheme => _scheme;

  set scheme(String value) {
    _scheme = value.toLowerCase();
  }

  String get host => _host;

  set host(String value) {
    _host = value.toLowerCase();
  }

  int? get port => _port;

  set port(int? value) {
    _port = value == 0
        ? value
        : (value != null)
            ? int.tryParse(value.toString(), radix: 10)
            : null;
  }

  void setParam(String? key, dynamic value) {
    if (key != null) {
      _parameters[key.toLowerCase()] =
          (value == null) ? null : value.toString();
    }
  }

  dynamic getParam(String? key) {
    if (key != null) {
      return _parameters[key.toLowerCase()];
    }
    return null;
  }

  bool hasParam(String? key) {
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
    _parameters = <dynamic, dynamic>{};
  }

  void setHeader(String name, dynamic value) {
    _headers[utils.headerize(name)] =
        (value is List) ? value : <dynamic>[value];
  }

  dynamic getHeader(String? name) {
    if (name != null) {
      return _headers[utils.headerize(name)];
    }
    return null;
  }

  bool hasHeader(String? name) {
    if (name != null) {
      return (_headers.containsKey(utils.headerize(name)) && true) || false;
    }
    return false;
  }

  dynamic deleteHeader(String header) {
    header = utils.headerize(header);
    if (_headers.containsKey(header)) {
      dynamic value = _headers[header];
      _headers.remove(header);
      return value;
    }
    return null;
  }

  void clearHeaders() {
    _headers = <dynamic, dynamic>{};
  }

  URI clone() {
    return URI(
        scheme,
        user,
        host,
        port,
        decoder.convert(encoder.convert(_parameters)),
        decoder.convert(encoder.convert(_headers)));
  }

  @override
  String toString() {
    List<String> headers = <String>[];

    String uri = '$_scheme:';

    if (user != null) {
      uri += '${utils.escapeUser(user!)}@';
    }
    uri += host;
    if (port != null || port == 0) {
      uri += ':${port.toString()}';
    }

    _parameters.forEach((dynamic key, dynamic parameter) {
      uri += ';$key';
      if (_parameters[key] != null) {
        uri += '=${_parameters[key].toString()}';
      }
    });

    _headers.forEach((dynamic key, dynamic header) {
      dynamic hdrs = _headers[key];
      hdrs.forEach((dynamic item) {
        headers.add('${utils.headerize(key)}=${item.toString()}');
      });
    });

    if (headers.length > 0) {
      uri += '?${headers.join('&')}';
    }

    return uri;
  }

  String toAor({bool show_port = false}) {
    String aor = '$_scheme:';

    if (user != null) {
      aor += '${utils.escapeUser(user!)}@';
    }
    aor += _host;
    if (show_port && (_port != null || _port == 0)) {
      aor += ':$_port';
    }

    return aor;
  }
}
