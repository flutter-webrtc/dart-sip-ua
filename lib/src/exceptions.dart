import 'utils.dart';

class ErrorImpl extends Error {
  int code;
  String name;
  String parameter;
  dynamic value;
  String message;
  dynamic status;
}

class ConfigurationError extends ErrorImpl {
  ConfigurationError(String parameter, [dynamic value]) {
    code = 1;
    name = 'CONFIGURATION_ERROR';
    this.parameter = parameter;
    this.value = value;
    message = (value == null)
        ? 'Missing parameter: $parameter'
        : 'Invalid value ${encoder.convert(value)} for parameter "$parameter"';
  }
}

class InvalidStateError extends ErrorImpl {
  InvalidStateError(dynamic status) {
    code = 2;
    name = 'INVALID_STATE_ERROR';
    this.status = status;
    message = 'Invalid status: ${status.toString()}';
  }
}

class NotSupportedError extends ErrorImpl {
  NotSupportedError(String message) {
    code = 3;
    name = 'NOT_SUPPORTED_ERROR';
    this.message = message;
  }
}

class NotReadyError extends ErrorImpl {
  NotReadyError(String message) {
    code = 4;
    name = 'NOT_READY_ERROR';
    this.message = message;
  }
}

class TypeError extends AssertionError {
  TypeError(String message) : super(message);
}
