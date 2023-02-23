import 'dart:convert' show utf8;

import 'package:sdp_transform/sdp_transform.dart' as sdp_transform;

import 'package:sip_ua/src/transactions/transaction_base.dart';
import 'constants.dart' as DartSIP_C;
import 'constants.dart';
import 'data.dart';
import 'exceptions.dart' as Exceptions;
import 'grammar.dart';
import 'logger.dart';
import 'name_addr_header.dart';
import 'transport.dart';
import 'ua.dart';
import 'uri.dart';
import 'utils.dart' as utils;

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
  OutgoingRequest(this.method, this.ruri, this.ua,
      [Map<String, dynamic>? params,
      List<dynamic>? extraHeaders,
      String? body]) {
    // Mandatory parameters check.
    if (method == null || ruri == null || ua == null) {
      throw Exceptions.TypeError('OutgoingRequest: ctor parameters invalid!');
    }

    params = params ?? <String, dynamic>{};
    // ignore: prefer_initializing_formals
    this.body = body;
    if (extraHeaders != null)
      this.extraHeaders = utils.cloneArray(extraHeaders);

    // Fill the Common SIP Request Headers.

    // Route.
    if (params['route_set'] != null) {
      setHeader('route', params['route_set']);
    } else if (ua.configuration.use_preloaded_route) {
      setHeader('route', '<${ua.transport!.sip_uri};lr>');
    }

    // Via.
    // Empty Via header. Will be filled by the client transaction.
    setHeader('via', '');

    // Max-Forwards.
    setHeader('max-forwards', DartSIP_C.MAX_FORWARDS);

    // To
    dynamic to_uri = params['to_uri'] ?? ruri;
    dynamic to_params = params['to_tag'] != null
        ? <String, dynamic>{'tag': params['to_tag']}
        : null;
    String? to_display_name = params['to_display_name'];

    to = NameAddrHeader(to_uri, to_display_name, to_params);
    setHeader('to', to.toString());

    // From.
    dynamic from_uri = params['from_uri'] ?? ua.configuration.uri;
    Map<String, dynamic> from_params = <String, dynamic>{
      'tag': params['from_tag'] ?? utils.newTag()
    };
    String? display_name;

    if (params['from_display_name'] != null) {
      display_name = params['from_display_name'];
    } else if (ua.configuration.display_name != null) {
      display_name = ua.configuration.display_name;
    } else {
      display_name = null;
    }

    from = NameAddrHeader(from_uri, display_name, from_params);
    setHeader('from', from.toString());

    // Call-ID.
    String call_id = params['call_id'] ??
        (ua.configuration.jssip_id! + utils.createRandomToken(15));

    this.call_id = call_id;
    setHeader('call-id', call_id);

    // CSeq.
    num cseq = params['cseq'] ?? (utils.Math.randomDouble() * 10000).floor();

    this.cseq = cseq as int?;
    setHeader('cseq', '$cseq ${SipMethodHelper.getName(method)}');
  }

  UA ua;
  Map<String?, dynamic> headers = <String?, dynamic>{};
  SipMethod method;
  URI? ruri;
  String? body;
  List<dynamic> extraHeaders = <dynamic>[];
  NameAddrHeader? to;
  NameAddrHeader? from;
  String? call_id;
  int? cseq;
  Map<String, dynamic>? sdp;
  dynamic transaction;

  /**
   * Replace the the given header by the given value.
   * -param {String} name header name
   * -param {String | Array} value header value
   */
  void setHeader(String name, dynamic value) {
    // Remove the header from extraHeaders if present.
    RegExp regexp = RegExp('^\\s*$name\\s*:', caseSensitive: false);

    for (int idx = 0; idx < extraHeaders.length; idx++) {
      if (regexp.hasMatch(extraHeaders[idx])) {
        extraHeaders.sublist(idx, 1);
      }
    }

    headers[utils.headerize(name)] = (value is List) ? value : <dynamic>[value];
  }

  /**
   * Get the value of the given header name at the given position.
   * -param {String} name header name
   * -returns {String|null} Returns the specified header, null if header doesn't exist.
   */
  dynamic getHeader(String name) {
    List<dynamic>? headers = this.headers[utils.headerize(name)];

    if (headers != null) {
      if (headers[0] != null) {
        return headers[0];
      }
    } else {
      RegExp regexp = RegExp('^\\s*$name\\s*:', caseSensitive: false);
      for (dynamic header in extraHeaders) {
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
  List<dynamic> getHeaders(String name) {
    List<dynamic>? headers = this.headers[utils.headerize(name)];
    List<dynamic> result = <dynamic>[];

    if (headers != null) {
      for (dynamic header in headers) {
        result.add(header);
      }

      return result;
    } else {
      RegExp regexp = RegExp('^\\s*$name\\s*:', caseSensitive: false);

      for (dynamic header in extraHeaders) {
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
  bool hasHeader(String name) {
    if (headers[utils.headerize(name)]) {
      return true;
    } else {
      RegExp regexp = RegExp('^\\s*$name\\s*:', caseSensitive: false);

      for (dynamic header in extraHeaders) {
        if (regexp.hasMatch(header)) {
          return true;
        }
      }
    }

    return false;
  }

  /**
   * Parse the current body as a SDP and store the resulting object
   * into sdp.
   * -param {Boolean} force: Parse even if sdp already exists.
   *
   * Returns sdp.
   */
  Map<String, dynamic>? parseSDP({bool force = false}) {
    if (!force && sdp != null) {
      return sdp;
    } else {
      sdp = sdp_transform.parse(body ?? '');
      return sdp;
    }
  }

  @override
  String toString() {
    String msg = '${SipMethodHelper.getName(method)} $ruri SIP/2.0\r\n';

    headers.forEach((String? headerName, dynamic headerValues) {
      headerValues.forEach((dynamic value) {
        msg += '$headerName: $value\r\n';
      });
    });

    for (dynamic header in extraHeaders) {
      msg += '${header.trim()}\r\n';
    }

    // Supported.
    List<dynamic> supported = <dynamic>[];

    switch (method) {
      case SipMethod.REGISTER:
        supported.add('path');
        supported.add('gruu');
        break;
      case SipMethod.INVITE:
        if (ua.configuration.session_timers) {
          supported.add('timer');
        }
        if (ua.contact!.pub_gruu != null || ua.contact!.temp_gruu != null) {
          supported.add('gruu');
        }
        supported.add('ice');
        supported.add('replaces');
        break;
      case SipMethod.UPDATE:
        if (ua.configuration.session_timers) {
          supported.add('timer');
        }
        supported.add('ice');
        break;
      default:
        break;
    }

    supported.add('outbound');

    String userAgent = ua.configuration.user_agent;

    // Allow.
    msg += 'Allow: ${DartSIP_C.ALLOWED_METHODS}\r\n';
    msg += 'Supported: ${supported.join(',')}\r\n';
    msg += 'User-Agent: $userAgent\r\n';

    if (body != null) {
      logger.d('Outgoing Message: ${body!}');
      //Here we should calculate the real content length for UTF8
      List<int> encoded = utf8.encode(body!);
      int length = encoded.length;
      msg += 'Content-Length: $length\r\n\r\n';
      msg += body!;
    } else {
      msg += 'Content-Length: 0\r\n\r\n';
    }

    return msg;
  }

  OutgoingRequest clone() {
    OutgoingRequest request = OutgoingRequest(method, ruri, ua);

    headers.forEach((String? name, dynamic value) {
      request.headers[name] = headers[name];
    });

    request.body = body;
    request.extraHeaders = utils.cloneArray(extraHeaders);
    request.to = to;
    request.from = from;
    request.call_id = call_id;
    request.cseq = cseq;

    return request;
  }
}

class InitialOutgoingInviteRequest extends OutgoingRequest {
  InitialOutgoingInviteRequest(URI? ruri, UA ua,
      [Map<String, dynamic>? params, List<dynamic>? extraHeaders, String? body])
      : super(SipMethod.INVITE, ruri, ua, params, extraHeaders, body) {
    transaction = null;
  }

  void cancel(String? reason) {
    transaction.cancel(reason);
  }

  @override
  InitialOutgoingInviteRequest clone() {
    InitialOutgoingInviteRequest request =
        InitialOutgoingInviteRequest(ruri, ua);

    headers.forEach((String? name, dynamic value) {
      request.headers[name] = List<dynamic>.from(headers[name]);
    });

    request.body = body;
    request.extraHeaders = utils.cloneArray(extraHeaders);
    request.to = to;
    request.from = from;
    request.call_id = call_id;
    request.cseq = cseq;

    request.transaction = transaction;

    return request;
  }
}

class IncomingMessage {
  IncomingMessage() {
    data = '';
    headers = null;
    method = null;
    via_branch = null;
    call_id = null;
    cseq = null;
    from = null;
    from_tag = null;
    to = null;
    to_tag = null;
    body = '';
    sdp = null;
  }

  late String data;
  Map<String?, dynamic>? headers;
  SipMethod? method;
  String? via_branch;
  String? call_id;
  int? cseq;
  NameAddrHeader? from;
  String? from_tag;
  NameAddrHeader? to;
  String? to_tag;
  String? body;
  Map<String, dynamic>? sdp;
  dynamic status_code;
  String? reason_phrase;
  int? session_expires;
  String? session_expires_refresher;
  ParsedData? event;
  late ParsedData replaces;
  dynamic refer_to;

  /**
  * Insert a header of the given name and value into the last position of the
  * header array.
  */
  void addHeader(String name, dynamic value) {
    Map<String, dynamic> header = <String, dynamic>{'raw': value};

    name = utils.headerize(name);

    if (headers![name] != null) {
      headers![name].add(header);
    } else {
      headers![name] = <dynamic>[header];
    }
  }

  /**
   * Get the value of the given header name at the given position.
   */
  dynamic getHeader(String name) {
    dynamic header = headers![utils.headerize(name)];

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
  List<dynamic> getHeaders(String name) {
    List<dynamic>? headers = this.headers![utils.headerize(name)];
    List<dynamic> result = <dynamic>[];

    if (headers == null) {
      return <dynamic>[];
    }

    for (dynamic header in headers) {
      result.add(header['raw']);
    }

    return result;
  }

  /**
   * Verify the existence of the given header.
   */
  bool hasHeader(String name) {
    return headers!.containsKey(utils.headerize(name));
  }

  /**
  * Parse the given header on the given index.
  * -param {String} name header name
  * -param {Number} [idx=0] header index
  * -returns {Object|null} Parsed header object, null if the header
  *  is not present or in case of a parsing error.
  */
  dynamic parseHeader(String name, {int idx = 0}) {
    name = utils.headerize(name);

    if (headers![name] == null) {
      logger.d('header "$name" not present');
      return null;
    } else if (idx >= headers![name].length) {
      logger.d('not so many "$name" headers present');
      return null;
    }

    dynamic header = headers![name][idx];
    dynamic value = header['raw'];

    if (header['parsed'] != null) {
      return header['parsed'];
    }

    // Substitute '-' by '_' for grammar rule matching.
    dynamic parsed = Grammar.parse(value, name.replaceAll('-', '_'));
    if (parsed == -1) {
      headers![name].splice(idx, 1); // delete from headers
      logger.d('error parsing "$name" header field with value "$value"');
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
  dynamic s(String name, {int idx = 0}) {
    return parseHeader(name, idx: idx);
  }

  /**
  * Replace the value of the given header by the value.
  * -param {String} name header name
  * -param {String} value header value
  */
  void setHeader(String name, dynamic value) {
    Map<String, dynamic> header = <String, dynamic>{'raw': value};

    headers![utils.headerize(name)] = <dynamic>[header];
  }

  /**
   * Parse the current body as a SDP and store the resulting object
   * into sdp.
   * -param {Boolean} force: Parse even if sdp already exists.
   *
   * Returns sdp.
   */
  Map<String, dynamic>? parseSDP({bool force = false}) {
    if (!force && sdp != null) {
      return sdp;
    } else {
      sdp = sdp_transform.parse(body ?? '');
      return sdp;
    }
  }

  @override
  String toString() {
    return data;
  }
}

class IncomingRequest extends IncomingMessage {
  IncomingRequest(this.ua) : super() {
    headers = <String?, dynamic>{};
    ruri = null;
    transport = null;
    server_transaction = null;
  }
  UA? ua;
  URI? ruri;
  Transport? transport;
  TransactionBase? server_transaction;
  /**
  * Stateful reply.
  * -param {Number} code status code
  * -param {String} reason reason phrase
  * -param {Object} headers extra headers
  * -param {String} body body
  * -param {Function} [onSuccess] onSuccess callback
  * -param {Function} [onFailure] onFailure callback
  */
  void reply(int code,
      [String? reason,
      List<dynamic>? extraHeaders,
      String? body,
      Function? onSuccess,
      Function? onFailure]) {
    List<dynamic> supported = <dynamic>[];
    dynamic to = getHeader('To');

    reason = reason ?? null;

    // Validate code and reason values.
    if (code < 100 || code > 699) {
      throw Exceptions.TypeError('Invalid status_code: $code');
    } else if (reason != null) {
      throw Exceptions.TypeError('Invalid reason_phrase: $reason');
    }

    reason = reason ?? DartSIP_C.REASON_PHRASE[code] ?? '';
    if (extraHeaders != null) extraHeaders = utils.cloneArray(extraHeaders);

    String response = 'SIP/2.0 $code $reason\r\n';

    if (method == SipMethod.INVITE && code > 100 && code <= 200) {
      List<dynamic> headers = getHeaders('record-route');

      for (dynamic header in headers) {
        response += 'Record-Route: $header\r\n';
      }
    }

    List<dynamic> vias = getHeaders('via');

    for (dynamic via in vias) {
      response += 'Via: $via\r\n';
    }

    if (to_tag == null && code > 100) {
      to += ';tag=${utils.newTag()}';
    } else if (to_tag != null && !s('to').hasParam('tag')) {
      to += ';tag=$to_tag';
    }

    response += 'To: $to\r\n';
    response += 'From: ${getHeader('From')}\r\n';
    response += 'Call-ID: $call_id\r\n';
    response += 'CSeq: $cseq ${SipMethodHelper.getName(method)}\r\n';

    if (extraHeaders != null)
      for (dynamic header in extraHeaders) {
        response += '${header.trim()}\r\n';
      }

    // Supported.
    switch (method) {
      case SipMethod.INVITE:
        if (ua!.configuration.session_timers) {
          supported.add('timer');
        }
        if (ua!.contact!.pub_gruu != null || ua!.contact!.temp_gruu != null) {
          supported.add('gruu');
        }
        supported.add('ice');
        supported.add('replaces');
        break;
      case SipMethod.UPDATE:
        if (ua!.configuration.session_timers) {
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
    if (method == SipMethod.OPTIONS) {
      response += 'Allow: ${DartSIP_C.ALLOWED_METHODS}\r\n';
      response += 'Accept: ${DartSIP_C.ACCEPTED_BODY_TYPES}\r\n';
    } else if (code == 405) {
      response += 'Allow: ${DartSIP_C.ALLOWED_METHODS}\r\n';
    } else if (code == 415) {
      response += 'Accept: ${DartSIP_C.ACCEPTED_BODY_TYPES}\r\n';
    }

    response += 'Supported: ${supported.join(',')}\r\n';

    if (body != null) {
      int length = body.length;

      response += 'Content-Type: application/sdp\r\n';
      response += 'Content-Length: $length\r\n\r\n';
      response += body;
    } else {
      response += 'Content-Length: ${0}\r\n\r\n';
    }

    IncomingMessage message = IncomingMessage();
    message.data = response;

    server_transaction!.receiveResponse(code, message,
        onSuccess as void Function()?, onFailure as void Function()?);
  }

  /**
  * Stateless reply.
  * -param {Number} code status code
  * -param {String} reason reason phrase
  */
  void reply_sl(int code, [String? reason]) {
    List<dynamic> vias = getHeaders('via');

    // Validate code and reason values.
    if (code == null || (code < 100 || code > 699)) {
      throw Exceptions.TypeError('Invalid status_code: $code');
    } else if (reason != null) {
      throw Exceptions.TypeError('Invalid reason_phrase: $reason');
    }

    reason = reason ?? DartSIP_C.REASON_PHRASE[code] ?? '';

    String response = 'SIP/2.0 $code $reason\r\n';

    for (dynamic via in vias) {
      response += 'Via: $via\r\n';
    }

    dynamic to = getHeader('To');

    if (to_tag == null && code > 100) {
      to += ';tag=${utils.newTag()}';
    } else if (to_tag != null && !s('to').hasParam('tag')) {
      to += ';tag=$to_tag';
    }

    response += 'To: $to\r\n';
    response += 'From: ${getHeader('From')}\r\n';
    response += 'Call-ID: $call_id\r\n';
    response += 'CSeq: $cseq ${SipMethodHelper.getName(method)}\r\n';
    response += 'Content-Length: ${0}\r\n\r\n';

    transport!.send(response);
  }
}

class IncomingResponse extends IncomingMessage {
  IncomingResponse() {
    headers = <String?, dynamic>{};
    status_code = null;
    reason_phrase = null;
  }
}
