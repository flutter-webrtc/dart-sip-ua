import 'dart:convert';
import 'uri.dart';
import 'grammar.dart';

class NameAddrHeader {
  final JsonDecoder decoder = new JsonDecoder();
  final JsonEncoder encoder = new JsonEncoder();
  URI _uri;
  Map<String, dynamic> _parameters;
  String _display_name;
  /**
   * Parse the given string and returns a NameAddrHeader instance or null if
   * it is an invalid NameAddrHeader.
   */
  static parse(name_addr_header) {
    name_addr_header = Grammar.parse(name_addr_header, 'Name_Addr_Header');

    if (name_addr_header != -1) {
      return name_addr_header;
    } else {
      return null;
    }
  }

  NameAddrHeader(uri, display_name, [parameters]) {
    // Checks.
    if (uri == null || uri is! URI) {
      throw new AssertionError('missing or invalid "uri" parameter');
    }

    // Initialize parameters.
    this._uri = uri;
    this._parameters = {};
    this._display_name = display_name;

    if (parameters != null) {
      parameters.forEach((key, param) {
        this.setParam(key, param);
      });
    }
  }

  URI get uri => _uri;

  String get display_name => _display_name;

  set display_name(dynamic value) {
    this._display_name = (value == 0) ? '0' : value;
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
      return this._parameters.containsKey(key.toLowerCase());
    }
    return false;
  }

  deleteParam(parameter) {
    parameter = parameter.toLowerCase();
    if (this._parameters[parameter] != null) {
      var value = this._parameters[parameter];
      this._parameters.remove(parameter);
      return value;
    }
  }

  clearParams() {
    this._parameters = {};
  }

  clone() {
    return new NameAddrHeader(this._uri.clone(), this._display_name,
        decoder.convert(encoder.convert(this._parameters)));
  }

  _quote(str) {
    return str.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }

  toString() {
    var body = (this._display_name != null && this._display_name.length > 0)
        ? '"${this._quote(this._display_name)}" '
        : '';

    body += '<${this._uri.toString()}>';

    this._parameters.forEach((key, value) {
      if (this._parameters.containsKey(key)) {
        body += ';${key}';
        if (value != null) {
          body += '=${value}';
        }
      }
    });

    return body;
  }
}
