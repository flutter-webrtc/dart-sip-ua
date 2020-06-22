import 'dart:convert' show utf8;
import 'package:sdp_transform/sdp_transform.dart' as sdp_transform;

import '../sip_ua.dart';
import 'constants.dart';
import 'constants.dart' as DartSIP_C;
import 'exceptions.dart' as Exceptions;
import 'grammar.dart';
import 'name_addr_header.dart';
import 'ua.dart';
import 'utils.dart' as Utils;
import 'grammar_parser.dart';
import 'logger.dart';
import 'transactions/transaction_base.dart';

final logger = Log();

/**
 * -param {String} method request method
 * -param {String} ruri request uri
 * -param {UA} ua
 * -param {Object} params parameters that will have priority over ua.configuration parameters:
 * <br>
 *  - cseq, call_id, from_tag, from_uri, from_display_name, to_uri, to_tag, route_set
 * -param {Object} [headers] extra headers
 * -param {String} [body]
 */
class OutgoingRequest {
  UA ua;
  var headers;
  SipMethod method;
  var ruri;
  var body;
  var extraHeaders = [];
  var to;
  var from;
  var call_id;
  var cseq;
  var sdp;
  var transaction;

  OutgoingRequest(SipMethod method, ruri, UA ua, [params, extraHeaders, body]) {
    // Mandatory parameters check.
    if (method == null || ruri == null || ua == null) {
      throw new Exceptions.TypeError(
          'OutgoingRequest: ctor parameters invalid!');
    }

    params = params ?? {};

    this.ua = ua;
    this.headers = {};
    this.method = method;
    this.ruri = ruri;
    this.body = body;
    this.extraHeaders = Utils.cloneArray(extraHeaders);

    // Fill the Common SIP Request Headers.

    // Route.
    if (params['route_set'] != null) {
      this.setHeader('route', params['route_set']);
    } else if (ua.configuration.use_preloaded_route) {
      this.setHeader('route', '<${ua.transport.sip_uri};lr>');
    }

    // Via.
    // Empty Via header. Will be filled by the client transaction.
    this.setHeader('via', '');

    // Max-Forwards.
    this.setHeader('max-forwards', DartSIP_C.MAX_FORWARDS);

    // To
    var to_uri = params['to_uri'] ?? ruri;
    var to_params = params['to_tag'] != null ? {'tag': params['to_tag']} : null;
    var to_display_name = params['to_display_name'];

    this.to = new NameAddrHeader(to_uri, to_display_name, to_params);
    this.setHeader('to', this.to.toString());

    // From.
    var from_uri = params['from_uri'] ?? ua.configuration.uri;
    var from_params = {'tag': params['from_tag'] ?? Utils.newTag()};
    var display_name;

    if (params['from_display_name'] != null) {
      display_name = params['from_display_name'];
    } else if (ua.configuration.display_name != null) {
      display_name = ua.configuration.display_name;
    } else {
      display_name = null;
    }

    this.from = new NameAddrHeader(from_uri, display_name, from_params);
    this.setHeader('from', this.from.toString());

    // Call-ID.
    var call_id = params['call_id'] ??
        (ua.configuration.jssip_id + Utils.createRandomToken(15));

    this.call_id = call_id;
    this.setHeader('call-id', call_id);

    // CSeq.
    var cseq =
        params['cseq'] ?? Utils.Math.floor(Utils.Math.randomDouble() * 10000);

    this.cseq = cseq;
    this.setHeader('cseq', '${cseq} ${SipMethodHelper.getName(method)}');
  }

  /**
   * Replace the the given header by the given value.
   * -param {String} name header name
   * -param {String | Array} value header value
   */
  setHeader(name, value) {
    // Remove the header from extraHeaders if present.
    var regexp = new RegExp('^\\s*${name}\\s*:', caseSensitive: false);

    for (var idx = 0; idx < this.extraHeaders.length; idx++) {
      if (regexp.hasMatch(this.extraHeaders[idx])) {
        this.extraHeaders.sublist(idx, 1);
      }
    }

    this.headers[Utils.headerize(name)] = (value is List) ? value : [value];
  }

  /**
   * Get the value of the given header name at the given position.
   * -param {String} name header name
   * -returns {String|null} Returns the specified header, null if header doesn't exist.
   */
  getHeader(name) {
    var headers = this.headers[Utils.headerize(name)];

    if (headers != null) {
      if (headers[0] != null) {
        return headers[0];
      }
    } else {
      var regexp = new RegExp('^\\s*${name}\\s*:', caseSensitive: false);
      for (var header in this.extraHeaders) {
        if (regexp.hasMatch(header)) {
          return header.substring(header.indexOf(':') + 1).trim();
        }
      }
    }

    return null;
  }

  /**
   * Get the header/s of the given name.
   * -param {String} name header name
   * -returns {Array} Array with all the headers of the specified name.
   */
  getHeaders(name) {
    var headers = this.headers[Utils.headerize(name)];
    var result = [];

    if (headers != null) {
      for (var header in headers) {
        result.add(header);
      }

      return result;
    } else {
      var regexp = new RegExp('^\\s*${name}\\s*:', caseSensitive: false);

      for (var header in this.extraHeaders) {
        if (regexp.hasMatch(header)) {
          result.add(header.substring(header.indexOf(':') + 1).trim());
        }
      }

      return result;
    }
  }

  /**
   * Verify the existence of the given header.
   * -param {String} name header name
   * -returns {boolean} true if header with given name exists, false otherwise
   */
  hasHeader(name) {
    if (this.headers[Utils.headerize(name)]) {
      return true;
    } else {
      var regexp = new RegExp('^\\s*${name}\\s*:', caseSensitive: false);

      for (var header in this.extraHeaders) {
        if (regexp.hasMatch(header)) {
          return true;
        }
      }
    }

    return false;
  }

  /**
   * Parse the current body as a SDP and store the resulting object
   * into this.sdp.
   * -param {Boolean} force: Parse even if this.sdp already exists.
   *
   * Returns this.sdp.
   */
  parseSDP({force = false}) {
    if (!force && this.sdp != null) {
      return this.sdp;
    } else {
      this.sdp = sdp_transform.parse(this.body ?? '');
      return this.sdp;
    }
  }

  toString() {
    var msg =
        '${SipMethodHelper.getName(this.method)} ${this.ruri} SIP/2.0\r\n';

    this.headers.forEach((headerName, headerValues) {
      headerValues.forEach((value) {
        msg += '$headerName: $value\r\n';
      });
    });

    this.extraHeaders.forEach((header) {
      msg += '${header.trim()}\r\n';
    });

    // Supported.
    var supported = [];

    switch (this.method) {
      case SipMethod.REGISTER:
        supported.add('path');
        supported.add('gruu');
        break;
      case SipMethod.INVITE:
        if (this.ua.configuration.session_timers) {
          supported.add('timer');
        }
        if (this.ua.contact.pub_gruu != null ||
            this.ua.contact.temp_gruu != null) {
          supported.add('gruu');
        }
        supported.add('ice');
        supported.add('replaces');
        break;
      case SipMethod.UPDATE:
        if (this.ua.configuration.session_timers) {
          supported.add('timer');
        }
        supported.add('ice');
        break;
      default:
        break;
    }

    supported.add('outbound');

    var userAgent = this.ua.configuration.user_agent ?? DartSIP_C.USER_AGENT;

    // Allow.
    msg += 'Allow: ${DartSIP_C.ALLOWED_METHODS}\r\n';
    msg += 'Supported: ${supported.join(',')}\r\n';
    msg += 'User-Agent: ${userAgent}\r\n';

    if (this.body != null) {
      logger.debug("Outgoing Message: " + this.body);
      //Here we should calculate the real content length for UTF8
      var encoded = utf8.encode(this.body);
      var length = encoded.length;
      msg += 'Content-Length: ${length}\r\n\r\n';
      msg += this.body;
    } else {
      msg += 'Content-Length: 0\r\n\r\n';
    }

    return msg;
  }

  clone() {
    var request = new OutgoingRequest(this.method, this.ruri, this.ua);

    this.headers.forEach((name, value) {
      request.headers[name] = this.headers[name];
    });

    request.body = this.body;
    request.extraHeaders = Utils.cloneArray(this.extraHeaders);
    request.to = this.to;
    request.from = this.from;
    request.call_id = this.call_id;
    request.cseq = this.cseq;

    return request;
  }
}

class InitialOutgoingInviteRequest extends OutgoingRequest {
  InitialOutgoingInviteRequest(ruri, ua, [params, extraHeaders, body])
      : super(SipMethod.INVITE, ruri, ua, params, extraHeaders, body) {
    this.transaction = null;
  }

  cancel(reason) {
    this.transaction.cancel(reason);
  }

  clone() {
    var request = new InitialOutgoingInviteRequest(this.ruri, this.ua);

    this.headers.forEach((name, value) {
      request.headers[name] = new List.from(this.headers[name]);
    });

    request.body = this.body;
    request.extraHeaders = Utils.cloneArray(this.extraHeaders);
    request.to = this.to;
    request.from = this.from;
    request.call_id = this.call_id;
    request.cseq = this.cseq;

    request.transaction = this.transaction;

    return request;
  }
}

class IncomingMessage {
  String data;
  var headers;
  SipMethod method;
  var via;
  var via_branch;
  var call_id;
  var cseq;
  var from;
  var from_tag;
  var to;
  var to_tag;
  String body;
  var sdp;
  var status_code;
  var reason_phrase;
  var session_expires;
  var session_expires_refresher;
  Data event;
  dynamic replaces;
  dynamic refer_to;

  IncomingMessage() {
    this.data = '';
    this.headers = null;
    this.method = null;
    this.via = null;
    this.via_branch = null;
    this.call_id = null;
    this.cseq = null;
    this.from = null;
    this.from_tag = null;
    this.to = null;
    this.to_tag = null;
    this.body = '';
    this.sdp = null;
  }

  /**
  * Insert a header of the given name and value into the last position of the
  * header array.
  */
  addHeader(name, value) {
    var header = {'raw': value};

    name = Utils.headerize(name);

    if (this.headers[name] != null) {
      this.headers[name].add(header);
    } else {
      this.headers[name] = [header];
    }
  }

  /**
   * Get the value of the given header name at the given position.
   */
  getHeader(name) {
    var header = this.headers[Utils.headerize(name)];

    if (header != null) {
      if (header[0] != null) {
        return header[0]['raw'];
      }
    } else {
      return null;
    }
  }

  /**
   * Get the header/s of the given name.
   */
  getHeaders(name) {
    var headers = this.headers[Utils.headerize(name)];
    var result = [];

    if (headers == null) {
      return [];
    }

    for (var header in headers) {
      result.add(header['raw']);
    }

    return result;
  }

  /**
   * Verify the existence of the given header.
   */
  bool hasHeader(name) {
    return this.headers.containsKey(Utils.headerize(name));
  }

  /**
  * Parse the given header on the given index.
  * -param {String} name header name
  * -param {Number} [idx=0] header index
  * -returns {Object|null} Parsed header object, null if the header
  *  is not present or in case of a parsing error.
  */
  parseHeader(name, {idx = 0}) {
    name = Utils.headerize(name);

    if (this.headers[name] == null) {
      logger.debug('header "${name}" not present');
      return null;
    } else if (idx >= this.headers[name].length) {
      logger.debug('not so many "${name}" headers present');
      return null;
    }

    var header = this.headers[name][idx];
    var value = header['raw'];

    if (header['parsed'] != null) {
      return header['parsed'];
    }

    // Substitute '-' by '_' for grammar rule matching.
    var parsed = Grammar.parse(value, name.replaceAll('-', '_'));
    if (parsed == -1) {
      this.headers[name].splice(idx, 1); // delete from headers
      logger
          .debug('error parsing "${name}" header field with value "${value}"');
      return null;
    } else {
      header['parsed'] = parsed;

      return parsed;
    }
  }

  /**
   * Message Header attribute selector. Alias of parseHeader.
   * -param {String} name header name
   * -param {Number} [idx=0] header index
   * -returns {Object|null} Parsed header object, null if the header
   *  is not present or in case of a parsing error.
   *
   * -example
   * message.s('via',3).port
   */
  s(name, {idx = 0}) {
    return this.parseHeader(name, idx: idx);
  }

  /**
  * Replace the value of the given header by the value.
  * -param {String} name header name
  * -param {String} value header value
  */
  setHeader(name, value) {
    var header = {'raw': value};

    this.headers[Utils.headerize(name)] = [header];
  }

  /**
   * Parse the current body as a SDP and store the resulting object
   * into this.sdp.
   * -param {Boolean} force: Parse even if this.sdp already exists.
   *
   * Returns this.sdp.
   */
  parseSDP({force = false}) {
    if (!force && this.sdp != null) {
      return this.sdp;
    } else {
      this.sdp = sdp_transform.parse(this.body ?? '');
      return this.sdp;
    }
  }

  toString() {
    return this.data;
  }
}

class IncomingRequest extends IncomingMessage {
  UA ua;
  var ruri;
  var transport;
  TransactionBase server_transaction;

  IncomingRequest(UA ua) : super() {
    this.ua = ua;
    this.headers = {};
    this.ruri = null;
    this.transport = null;
    this.server_transaction = null;
  }

  /**
  * Stateful reply.
  * -param {Number} code status code
  * -param {String} reason reason phrase
  * -param {Object} headers extra headers
  * -param {String} body body
  * -param {Function} [onSuccess] onSuccess callback
  * -param {Function} [onFailure] onFailure callback
  */
  reply(code, [reason, extraHeaders, body, onSuccess, onFailure]) {
    var supported = [];
    var to = this.getHeader('To');

    code = code ?? null;
    reason = reason ?? null;

    // Validate code and reason values.
    if (code == null || (code < 100 || code > 699)) {
      throw new Exceptions.TypeError('Invalid status_code: ${code}');
    } else if (reason != null && reason is! String) {
      throw new Exceptions.TypeError('Invalid reason_phrase: ${reason}');
    }

    reason = reason ?? DartSIP_C.REASON_PHRASE[code] ?? '';
    extraHeaders = Utils.cloneArray(extraHeaders);

    var response = 'SIP/2.0 ${code} ${reason}\r\n';

    if (this.method == SipMethod.INVITE && code > 100 && code <= 200) {
      var headers = this.getHeaders('record-route');

      for (var header in headers) {
        response += 'Record-Route: ${header}\r\n';
      }
    }

    var vias = this.getHeaders('via');

    for (var via in vias) {
      response += 'Via: ${via}\r\n';
    }

    if (this.to_tag == null && code > 100) {
      to += ';tag=${Utils.newTag()}';
    } else if (this.to_tag != null && !this.s('to').hasParam('tag')) {
      to += ';tag=${this.to_tag}';
    }

    response += 'To: ${to}\r\n';
    response += 'From: ${this.getHeader('From')}\r\n';
    response += 'Call-ID: ${this.call_id}\r\n';
    response +=
        'CSeq: ${this.cseq} ${SipMethodHelper.getName(this.method)}\r\n';

    for (var header in extraHeaders) {
      response += '${header.trim()}\r\n';
    }

    // Supported.
    switch (this.method) {
      case SipMethod.INVITE:
        if (this.ua.configuration.session_timers) {
          supported.add('timer');
        }
        if (this.ua.contact.pub_gruu != null ||
            this.ua.contact.temp_gruu != null) {
          supported.add('gruu');
        }
        supported.add('ice');
        supported.add('replaces');
        break;
      case SipMethod.UPDATE:
        if (this.ua.configuration.session_timers) {
          supported.add('timer');
        }
        if (body != null) {
          supported.add('ice');
        }
        supported.add('replaces');
        break;
      default:
        break;
    }

    supported.add('outbound');

    // Allow and Accept.
    if (this.method == SipMethod.OPTIONS) {
      response += 'Allow: ${DartSIP_C.ALLOWED_METHODS}\r\n';
      response += 'Accept: ${DartSIP_C.ACCEPTED_BODY_TYPES}\r\n';
    } else if (code == 405) {
      response += 'Allow: ${DartSIP_C.ALLOWED_METHODS}\r\n';
    } else if (code == 415) {
      response += 'Accept: ${DartSIP_C.ACCEPTED_BODY_TYPES}\r\n';
    }

    response += 'Supported: ${supported.join(',')}\r\n';

    if (body != null) {
      var length = body.length;

      response += 'Content-Type: application/sdp\r\n';
      response += 'Content-Length: $length\r\n\r\n';
      response += body;
    } else {
      response += 'Content-Length: ${0}\r\n\r\n';
    }

    IncomingMessage message = IncomingMessage();
    message.data = response;

    this
        .server_transaction
        .receiveResponse(code, message, onSuccess, onFailure);
  }

  /**
  * Stateless reply.
  * -param {Number} code status code
  * -param {String} reason reason phrase
  */
  reply_sl(code, [reason]) {
    var vias = this.getHeaders('via');

    // Validate code and reason values.
    if (code == null || (code < 100 || code > 699)) {
      throw new Exceptions.TypeError('Invalid status_code: ${code}');
    } else if (reason != null && reason is! String) {
      throw new Exceptions.TypeError('Invalid reason_phrase: ${reason}');
    }

    reason = reason ?? DartSIP_C.REASON_PHRASE[code] ?? '';

    var response = 'SIP/2.0 ${code} ${reason}\r\n';

    for (var via in vias) {
      response += 'Via: ${via}\r\n';
    }

    var to = this.getHeader('To');

    if (this.to_tag == null && code > 100) {
      to += ';tag=${Utils.newTag()}';
    } else if (this.to_tag != null && !this.s('to').hasParam('tag')) {
      to += ';tag=${this.to_tag}';
    }

    response += 'To: ${to}\r\n';
    response += 'From: ${this.getHeader('From')}\r\n';
    response += 'Call-ID: ${this.call_id}\r\n';
    response +=
        'CSeq: ${this.cseq} ${SipMethodHelper.getName(this.method)}\r\n';
    response += 'Content-Length: ${0}\r\n\r\n';

    this.transport.send(response);
  }
}

class IncomingResponse extends IncomingMessage {
  IncomingResponse() {
    this.headers = {};
    this.status_code = null;
    this.reason_phrase = null;
  }
}
