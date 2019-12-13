import 'dart:convert';

class ErrorImpl extends Error {
  final JsonEncoder encoder = new JsonEncoder();
  var code;
  var name;
  var parameter;
  var value;
  var message;
  var status;
}

class ConfigurationError extends ErrorImpl {
  ConfigurationError(parameter, [value]) {
    this.code = 1;
    this.name = 'CONFIGURATION_ERROR';
    this.parameter = parameter;
    this.value = value;
    this.message = (this.value == null)
        ? 'Missing parameter: ${this.parameter}'
        : 'Invalid value ${encoder.convert(this.value)} for parameter "${this.parameter}"';
  }
}

class InvalidStateError extends ErrorImpl {
  InvalidStateError(status) {
    this.code = 2;
    this.name = 'INVALID_STATE_ERROR';
    this.status = status;
    this.message = 'Invalid status: ${status.toString()}';
  }
}

class NotSupportedError extends ErrorImpl {
  NotSupportedError(message) {
    this.code = 3;
    this.name = 'NOT_SUPPORTED_ERROR';
    this.message = message;
  }
}

class NotReadyError extends ErrorImpl {
  NotReadyError(message) {
    this.code = 4;
    this.name = 'NOT_READY_ERROR';
    this.message = message;
  }
}

class TypeError extends AssertionError {
  TypeError(message) : super(message);
}
