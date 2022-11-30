const String USER_AGENT = 'dart-sip-ua v0.5.3';

// SIP scheme.
const String SIP = 'sip';
const String SIPS = 'sips';

// End and Failure causes.
class Causes {
  // Generic error causes.
  static const String CONNECTION_ERROR = 'Connection Error';
  static const String REQUEST_TIMEOUT = 'Request Timeout';
  static const String SIP_FAILURE_CODE = 'SIP Failure Code';
  static const String INTERNAL_ERROR = 'Internal Error';

  // SIP error causes.
  static const String BUSY = 'Busy';
  static const String REJECTED = 'Rejected';
  static const String REDIRECTED = 'Redirected';
  static const String UNAVAILABLE = 'Unavailable';
  static const String NOT_FOUND = 'Not Found';
  static const String ADDRESS_INCOMPLETE = 'Address Incomplete';
  static const String INCOMPATIBLE_SDP = 'Incompatible SDP';
  static const String MISSING_SDP = 'Missing SDP';
  static const String AUTHENTICATION_ERROR = 'Authentication Error';

  // Session error causes.
  static const String BYE = 'Terminated';
  static const String WEBRTC_ERROR = 'WebRTC Error';
  static const String CANCELED = 'Canceled';
  static const String NO_ANSWER = 'No Answer';
  static const String EXPIRES = 'Expires';
  static const String NO_ACK = 'No ACK';
  static const String DIALOG_ERROR = 'Dialog Error';
  static const String USER_DENIED_MEDIA_ACCESS = 'User Denied Media Access';
  static const String BAD_MEDIA_DESCRIPTION = 'Bad Media Description';
  static const String RTP_TIMEOUT = 'RTP Timeout';
}

Map<String, List<int>> SIP_ERROR_CAUSES = <String, List<int>>{
  Causes.REDIRECTED: <int>[300, 301, 302, 305, 380],
  Causes.BUSY: <int>[486, 600],
  Causes.REJECTED: <int>[403, 603],
  Causes.NOT_FOUND: <int>[404, 604],
  Causes.UNAVAILABLE: <int>[480, 410, 408, 430],
  Causes.ADDRESS_INCOMPLETE: <int>[484, 424],
  Causes.INCOMPATIBLE_SDP: <int>[488, 606],
  Causes.AUTHENTICATION_ERROR: <int>[401, 407]
};

class CausesType {
  static const String CONNECTION_ERROR = Causes.CONNECTION_ERROR;
  static const String REQUEST_TIMEOUT = Causes.REQUEST_TIMEOUT;
  static const String SIP_FAILURE_CODE = Causes.SIP_FAILURE_CODE;
  static const String INTERNAL_ERROR = Causes.INTERNAL_ERROR;

  // SIP error causes.
  static const String BUSY = Causes.BUSY;
  static const String REJECTED = Causes.REJECTED;
  static const String REDIRECTED = Causes.REDIRECTED;
  static const String UNAVAILABLE = Causes.UNAVAILABLE;
  static const String NOT_FOUND = Causes.NOT_FOUND;
  static const String ADDRESS_INCOMPLETE = Causes.ADDRESS_INCOMPLETE;
  static const String INCOMPATIBLE_SDP = Causes.INCOMPATIBLE_SDP;
  static const String MISSING_SDP = Causes.MISSING_SDP;
  static const String AUTHENTICATION_ERROR = Causes.AUTHENTICATION_ERROR;

  // Session error causes.
  static const String BYE = Causes.BYE;
  static const String WEBRTC_ERROR = Causes.WEBRTC_ERROR;
  static const String CANCELED = Causes.CANCELED;
  static const String NO_ANSWER = Causes.NO_ANSWER;
  static const String EXPIRES = Causes.EXPIRES;
  static const String NO_ACK = Causes.NO_ACK;
  static const String DIALOG_ERROR = Causes.DIALOG_ERROR;
  static const String USER_DENIED_MEDIA_ACCESS =
      Causes.USER_DENIED_MEDIA_ACCESS;
  static const String BAD_MEDIA_DESCRIPTION = Causes.BAD_MEDIA_DESCRIPTION;
  static const String RTP_TIMEOUT = Causes.RTP_TIMEOUT;
}

// SIP Methods.
/* replaced with ENUM !
  const ACK       = 'ACK';
  const BYE       = 'BYE';
  const CANCEL    = 'CANCEL';
  const INFO      = 'INFO';
  const INVITE    = 'INVITE';
  const MESSAGE   = 'MESSAGE';
  const NOTIFY    = 'NOTIFY';
  const OPTIONS   = 'OPTIONS';
  const REGISTER  = 'REGISTER';
  const REFER     = 'REFER';
  const UPDATE    = 'UPDATE';
  const SUBSCRIBE = 'SUBSCRIBE';
*/
enum SipMethod {
  ACK,
  BYE,
  CANCEL,
  GET,
  INFO,
  INVITE,
  MESSAGE,
  NOTIFY,
  OPTIONS,
  REGISTER,
  REFER,
  UPDATE,
  SUBSCRIBE
}

class SipMethodHelper {
  static String getName(SipMethod? method) {
    int period = method.toString().indexOf('.');
    return method.toString().substring(period + 1);
  }

  static SipMethod? fromString(String? name) {
    if (name != null) {
      String cleanName = name.toUpperCase();
      for (SipMethod method in SipMethod.values) {
        if (getName(method) == cleanName) {
          return method;
        }
      }
      return null;
    }
    return null;
  }
}

/* SIP Response Reasons
   * DOC: https://www.iana.org/assignments/sip-parameters
   * Copied from https://github.com/versatica/OverSIP/blob/master/lib/oversip/sip/constants.rb#L7
   */
Map<int, String> REASON_PHRASE = <int, String>{
  100: 'Trying',
  180: 'Ringing',
  181: 'Call Is Being Forwarded',
  182: 'Queued',
  183: 'Session Progress',
  199: 'Early Dialog Terminated', // draft-ietf-sipcore-199
  200: 'OK',
  202: 'Accepted', // RFC 3265
  204: 'No Notification', // RFC 5839
  300: 'Multiple Choices',
  301: 'Moved Permanently',
  302: 'Moved Temporarily',
  305: 'Use Proxy',
  380: 'Alternative Service',
  400: 'Bad Request',
  401: 'Unauthorized',
  402: 'Payment Required',
  403: 'Forbidden',
  404: 'Not Found',
  405: 'Method Not Allowed',
  406: 'Not Acceptable',
  407: 'Proxy Authentication Required',
  408: 'Request Timeout',
  410: 'Gone',
  412: 'Conditional Request Failed', // RFC 3903
  413: 'Request Entity Too Large',
  414: 'Request-URI Too Long',
  415: 'Unsupported Media Type',
  416: 'Unsupported URI Scheme',
  417: 'Unknown Resource-Priority', // RFC 4412
  420: 'Bad Extension',
  421: 'Extension Required',
  422: 'Session Interval Too Small', // RFC 4028
  423: 'Interval Too Brief',
  424: 'Bad Location Information', // RFC 6442
  428: 'Use Identity Header', // RFC 4474
  429: 'Provide Referrer Identity', // RFC 3892
  430: 'Flow Failed', // RFC 5626
  433: 'Anonymity Disallowed', // RFC 5079
  436: 'Bad Identity-Info', // RFC 4474
  437: 'Unsupported Certificate', // RFC 4744
  438: 'Invalid Identity Header', // RFC 4744
  439: 'First Hop Lacks Outbound Support', // RFC 5626
  440: 'Max-Breadth Exceeded', // RFC 5393
  469: 'Bad Info Package', // draft-ietf-sipcore-info-events
  470: 'Consent Needed', // RFC 5360
  478: 'Unresolvable Destination', // Custom code copied from Kamailio.
  480: 'Temporarily Unavailable',
  481: 'Call/Transaction Does Not Exist',
  482: 'Loop Detected',
  483: 'Too Many Hops',
  484: 'Address Incomplete',
  485: 'Ambiguous',
  486: 'Busy Here',
  487: 'Request Terminated',
  488: 'Not Acceptable Here',
  489: 'Bad Event', // RFC 3265
  491: 'Request Pending',
  493: 'Undecipherable',
  494: 'Security Agreement Required', // RFC 3329
  500: 'DartSIP Internal Error',
  501: 'Not Implemented',
  502: 'Bad Gateway',
  503: 'Service Unavailable',
  504: 'Server Time-out',
  505: 'Version Not Supported',
  513: 'Message Too Large',
  580: 'Precondition Failure', // RFC 3312
  600: 'Busy Everywhere',
  603: 'Decline',
  604: 'Does Not Exist Anywhere',
  606: 'Not Acceptable'
};

const String ALLOWED_METHODS =
    'INVITE,ACK,CANCEL,BYE,UPDATE,MESSAGE,OPTIONS,REFER,INFO,NOTIFY';
const String ACCEPTED_BODY_TYPES = 'application/sdp, application/dtmf-relay';
const int MAX_FORWARDS = 69;
const int SESSION_EXPIRES = 90;
const int MIN_SESSION_EXPIRES = 60;
