import 'dart:convert' show utf8;

import 'grammar.dart';
import 'logger.dart';
import 'sip_message.dart';
import 'ua.dart';

/**
 * Parse SIP Message
 */
IncomingMessage? parseMessage(String data, UA? ua) {
  IncomingMessage message;
  int bodyStart;
  int headerEnd = data.indexOf('\r\n');

  if (headerEnd == -1) {
    logger.e('parseMessage() | no CRLF found, not a SIP message');
    return null;
  }

  // Parse first line. Check if it is a Request or a Reply.
  String firstLine = data.substring(0, headerEnd);
  dynamic parsed;
  try {
    parsed = Grammar.parse(firstLine, 'Request_Response');
  } catch (FormatException) {
    // Catch exception and fake the expected -1 result
    parsed = -1;
  }

  if (parsed == -1) {
    logger.e(
        'parseMessage() | error parsing first line of SIP message: "$firstLine"');

    return null;
  } else if (parsed.status_code == null) {
    IncomingRequest incomingRequest = IncomingRequest(ua);
    incomingRequest.method = parsed.method;
    incomingRequest.ruri = parsed.uri;
    message = incomingRequest;
  } else {
    message = IncomingResponse();
    message.status_code = parsed.status_code;
    message.reason_phrase = parsed.reason_phrase;
  }

  message.data = data;
  int headerStart = headerEnd + 2;

  /* Loop over every line in data. Detect the end of each header and parse
  * it or simply add to the headers collection.
  */
  while (true) {
    headerEnd = getHeader(data, headerStart);

    // The SIP message has normally finished.
    if (headerEnd == -2) {
      bodyStart = headerStart + 2;
      break;
    }
    // Data.indexOf returned -1 due to a malformed message.
    else if (headerEnd == -1) {
      logger.e('parseMessage() | malformed message');

      return null;
    }

    parsed = parseHeader(message, data, headerStart, headerEnd);

    if (parsed != true) {
      logger.e('parseMessage() |${parsed['error']}');
      return null;
    }

    headerStart = headerEnd + 2;
  }

  /* RFC3261 18.3.
   * If there are additional bytes in the transport packet
   * beyond the end of the body, they MUST be discarded.
   */
  if (message.hasHeader('content-length')) {
    dynamic headerContentLength = message.getHeader('content-length');

    if (headerContentLength is String) {
      headerContentLength = int.tryParse(headerContentLength) ?? 0;
    }
    headerContentLength ??= 0;

    if (headerContentLength > 0) {
      List<int> actualContent = utf8.encode(data.substring(bodyStart));
      if (headerContentLength != actualContent.length)
        logger.w(
            '${message.method} received with content-length: $headerContentLength but actual length is: ${actualContent.length}');
      List<int> encodedBody = utf8.encode(data.substring(bodyStart));
      List<int> content = encodedBody.sublist(0, actualContent.length);
      message.body = utf8.decode(content);
    }
  } else {
    message.body = data.substring(bodyStart);
  }

  return message;
}

/**
 * Extract and parse every header of a SIP message.
 */
int getHeader(String data, int headerStart) {
  // 'start' position of the header.
  int start = headerStart;
  // 'end' position of the header.
  int end = 0;
  // 'partial end' position of the header.
  int partialEnd = 0;

  // End of message.
  if (data.substring(start, start + 2).contains(RegExp(r'(^\r\n)'))) {
    return -2;
  }

  while (end == 0) {
    // Partial End of Header.
    partialEnd = data.indexOf('\r\n', start);

    // 'indexOf' returns -1 if the value to be found never occurs.
    if (partialEnd == -1) {
      return partialEnd;
    }
    //if (!data.substring(partialEnd + 2, partialEnd + 4).match(/(^\r\n)/) && data.charAt(partialEnd + 2).match(/(^\s+)/))

    if (!data
            .substring(partialEnd + 2, partialEnd + 4)
            .contains(RegExp(r'(^\r\n)')) &&
        String.fromCharCode(data.codeUnitAt(partialEnd + 2))
            .contains(RegExp(r'(^\s+)'))) {
      // Not the end of the message. Continue from the next position.
      start = partialEnd + 2;
    } else {
      end = partialEnd;
    }
  }

  return end;
}

dynamic parseHeader(
    IncomingMessage message, String data, int headerStart, int headerEnd) {
  dynamic parsed;
  int hcolonIndex = data.indexOf(':', headerStart);
  String headerName = data.substring(headerStart, hcolonIndex).trim();
  String headerValue = data.substring(hcolonIndex + 1, headerEnd).trim();

  // If header-field is well-known, parse it.
  switch (headerName.toLowerCase()) {
    case 'via':
    case 'v':
      message.addHeader('via', headerValue);
      if (message.getHeaders('via').length == 1) {
        parsed = message.parseHeader('Via');
        if (parsed != null) {
          message.via_branch = parsed.branch;
        }
      } else {
        parsed = 0;
      }
      break;
    case 'from':
    case 'f':
      message.setHeader('from', headerValue);
      parsed = message.parseHeader('from');
      if (parsed != null) {
        message.from = parsed;
        message.from_tag = parsed.getParam('tag');
      }
      break;
    case 'to':
    case 't':
      message.setHeader('to', headerValue);
      parsed = message.parseHeader('to');
      if (parsed != null) {
        message.to = parsed;
        message.to_tag = parsed.getParam('tag');
      }
      break;
    case 'record-route':
      parsed = Grammar.parse(headerValue, 'Record_Route');

      if (parsed == -1) {
        parsed = null;
      } else {
        for (Map<String, dynamic> header in parsed) {
          message.addHeader('record-route', header['raw']);
          message.headers!['Record-Route']
                  [message.getHeaders('record-route').length - 1]['parsed'] =
              header['parsed'];
        }
      }
      break;
    case 'call-id':
    case 'i':
      message.setHeader('call-id', headerValue);
      parsed = message.parseHeader('call-id');
      if (parsed != null) {
        message.call_id = headerValue;
      }
      break;
    case 'contact':
    case 'm':
      parsed = Grammar.parse(headerValue, 'Contact');

      if (parsed == -1) {
        parsed = null;
      } else {
        for (Map<String, dynamic> header in parsed) {
          message.addHeader('contact', header['raw']);
          message.headers!['Contact'][message.getHeaders('contact').length - 1]
              ['parsed'] = header['parsed'];
        }
      }
      break;
    case 'content-length':
    case 'l':
      message.setHeader('content-length', headerValue);
      parsed = message.parseHeader('content-length');
      break;
    case 'content-type':
    case 'c':
      message.setHeader('content-type', headerValue);
      parsed = message.parseHeader('content-type');
      break;
    case 'cseq':
      message.setHeader('cseq', headerValue);
      parsed = message.parseHeader('cseq');
      if (parsed != null) {
        message.cseq = parsed.cseq;
      }
      if (message is IncomingResponse) {
        message.method = parsed.method;
      }
      break;
    case 'max-forwards':
      message.setHeader('max-forwards', headerValue);
      parsed = message.parseHeader('max-forwards');
      break;
    case 'www-authenticate':
      message.setHeader('www-authenticate', headerValue);
      parsed = message.parseHeader('www-authenticate');
      break;
    case 'proxy-authenticate':
      message.setHeader('proxy-authenticate', headerValue);
      parsed = message.parseHeader('proxy-authenticate');
      break;
    case 'session-expires':
    case 'x':
      message.setHeader('session-expires', headerValue);
      parsed = message.parseHeader('session-expires');
      if (parsed != null) {
        message.session_expires = parsed.expires;
        message.session_expires_refresher = parsed.refresher;
      }
      break;
    case 'refer-to':
    case 'r':
      message.setHeader('refer-to', headerValue);
      parsed = message.parseHeader('refer-to');
      if (parsed != null) {
        message.refer_to = parsed;
      }
      break;
    case 'replaces':
      message.setHeader('replaces', headerValue);
      parsed = message.parseHeader('replaces');
      if (parsed != null) {
        message.replaces = parsed;
      }
      break;
    case 'event':
    case 'o':
      message.setHeader('event', headerValue);
      parsed = message.parseHeader('event');
      if (parsed != null) {
        message.event = parsed;
      }
      break;
    default:
      // Do not parse this header.
      message.addHeader(headerName, headerValue);
      parsed = 0;
  }

  if (parsed == null) {
    return <String, dynamic>{'error': 'error parsing header "$headerName"'};
  } else {
    return true;
  }
}
