class Logger {
  String _tag;
  Logger(this._tag) {}

  void error(error) {
    print('[' + _tag + '] ERROR: ' + error);
  }

  void debug(msg) {
    print('[' + _tag + '] DEBUG: ' + msg);
  }

  void warn(msg) {
    print('[' + _tag + '] WARN: ' + msg);
  }

  void failure(error) {
    var log = '[' + _tag + '] FAILURE: ' + error;
    print(log);
    throw (log);
  }
}
