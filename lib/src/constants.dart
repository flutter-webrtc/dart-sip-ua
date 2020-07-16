var USER_AGENT = 'dart-sip-ua v0.2.2';

// SIP scheme.
var SIP = 'sip';
var SIPS = 'sips';

// End and Failure causes.
class Causes {
  // Generic error causes.
  static final CONNECTION_ERROR = 'Connection Error';
  static final REQUEST_TIMEOUT = 'Request Timeout';
  static final SIP_FAILURE_CODE = 'SIP Failure Code';
  static final INTERNAL_ERROR = 'Internal Error';

  // SIP error causes.
  static final BUSY = 'Busy';
  static final REJECTED = 'Rejected';
  static final REDIRECTED = 'Redirected';
  static final UNAVAILABLE = 'Unavailable';
  static final NOT_FOUND = 'Not Found';
  static final ADDRESS_INCOMPLETE = 'Address Incomplete';
  static final INCOMPATIBLE_SDP = 'Incompatible SDP';
  static final MISSING_SDP = 'Missing SDP';
  static final AUTHENTICATION_ERROR = 'Authentication Error';

  // Session error causes.
  static final BYE = 'Terminated';
  static final WEBRTC_ERROR = 'WebRTC Error';
  static final CANCELED = 'Canceled';
  static final NO_ANSWER = 'No Answer';
  static final EXPIRES = 'Expires';
  static final NO_ACK = 'No ACK';
  static final DIALOG_ERROR = 'Dialog Error';
  static final USER_DENIED_MEDIA_ACCESS = 'User Denied Media Access';
  static final BAD_MEDIA_DESCRIPTION = 'Bad Media Description';
  static final RTP_TIMEOUT = 'RTP Timeout';
}

var SIP_ERROR_CAUSES = {
  Causes.REDIRECTED: [300, 301, 302, 305, 380],
  Causes.BUSY: [486, 600],
  Causes.REJECTED: [403, 603],
  Causes.NOT_FOUND: [404, 604],
  Causes.UNAVAILABLE: [480, 410, 408, 430],
  Causes.ADDRESS_INCOMPLETE: [484, 424],
  Causes.INCOMPATIBLE_SDP: [488, 606],
  Causes.AUTHENTICATION_ERROR: [401, 407]
};

class causes {
  static final CONNECTION_ERROR = Causes.CONNECTION_ERROR;
  static final REQUEST_TIMEOUT = Causes.REQUEST_TIMEOUT;
  static final SIP_FAILURE_CODE = Causes.SIP_FAILURE_CODE;
  static final INTERNAL_ERROR = Causes.INTERNAL_ERROR;

  // SIP error causes.
  static final BUSY = Causes.BUSY;
  static final REJECTED = Causes.REJECTED;
  static final REDIRECTED = Causes.REDIRECTED;
  static final UNAVAILABLE = Causes.UNAVAILABLE;
  static final NOT_FOUND = Causes.NOT_FOUND;
  static final ADDRESS_INCOMPLETE = Causes.ADDRESS_INCOMPLETE;
  static final INCOMPATIBLE_SDP = Causes.INCOMPATIBLE_SDP;
  static final MISSING_SDP = Causes.MISSING_SDP;
  static final AUTHENTICATION_ERROR = Causes.AUTHENTICATION_ERROR;

  // Session error causes.
  static final BYE = Causes.BYE;
  static final WEBRTC_ERROR = Causes.WEBRTC_ERROR;
  static final CANCELED = Causes.CANCELED;
  static final NO_ANSWER = Causes.NO_ANSWER;
  static final EXPIRES = Causes.EXPIRES;
  static final NO_ACK = Causes.NO_ACK;
  static final DIALOG_ERROR = Causes.DIALOG_ERROR;
  static final USER_DENIED_MEDIA_ACCESS = Causes.USER_DENIED_MEDIA_ACCESS;
  static final BAD_MEDIA_DESCRIPTION = Causes.BAD_MEDIA_DESCRIPTION;
  static final RTP_TIMEOUT = Causes.RTP_TIMEOUT;
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
  static String getName(SipMethod method) {
    int period = method.toString().indexOf(".");
    return method.toString().substring(period + 1);
  }

  static SipMethod fromString(String name) {
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
var REASON_PHRASE = {
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

var ALLOWED_METHODS = 'INVITE,ACK,CANCEL,BYE,UPDATE,MESSAGE,OPTIONS,REFER,INFO';
var ACCEPTED_BODY_TYPES = 'application/sdp, application/dtmf-relay';
var MAX_FORWARDS = 69;
var SESSION_EXPIRES = 90;
var MIN_SESSION_EXPIRES = 60;
