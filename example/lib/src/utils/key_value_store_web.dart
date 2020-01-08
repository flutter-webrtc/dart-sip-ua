import 'dart:async';
import 'dart:convert';
import 'dart_html_dummy.dart' if (dart.library.js) 'dart:html';

class KeyValueStore {
  KeyValueStore();
  Storage _storage;

  void init() async {
    _storage = window.localStorage as Storage;
  }

  String getString(String key) => _storage[key];

  Future<bool> setString(String key, String value) => _setValue(key, value);

  Future<bool> _setValue(String key, dynamic value) {
    if (value is String) {
      _storage[key] = value;
    } else if (value is bool || value is double || value is int) {
      _storage[key] = value.toString();
    } else if (value is List) {
      _storage[key] = json.encode(value);
    }

    return Future.value(true);
  }
}
