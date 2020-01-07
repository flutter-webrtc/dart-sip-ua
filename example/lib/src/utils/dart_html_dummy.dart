/*
 * Theses classes simply serve to remove compile errors
 * when building for a flutter environment 
 */
class Storage {
  Map<String, String> store = Map();

  String operator [](String key) => store[key];
  operator []=(String key, String value) => store[key] = value;
}

dynamic window;
