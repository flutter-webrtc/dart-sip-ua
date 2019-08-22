
var USER_AGENT =  'dart-sip-ua v0.0.1';

  // SIP scheme.
var SIP  = 'sip';
var SIPS = 'sips';

  // End and Failure causes.
class Causes {
    // Generic error causes.
    static var CONNECTION_ERROR = 'Connection Error';
    static var REQUEST_TIMEOUT  = 'Request Timeout';
    static var SIP_FAILURE_CODE = 'SIP Failure Code';
    static var INTERNAL_ERROR   = 'Internal Error';

    // SIP error causes.
    static var BUSY                 = 'Busy';
    static var REJECTED             = 'Rejected';
    static var REDIRECTED           = 'Redirected';
    static var UNAVAILABLE          = 'Unavailable';
    static var NOT_FOUND            = 'Not Found';
    static var ADDRESS_INCOMPLETE   = 'Address Incomplete';
    static var INCOMPATIBLE_SDP     = 'Incompatible SDP';
    static var MISSING_SDP          = 'Missing SDP';
    static var AUTHENTICATION_ERROR = 'Authentication Error';

    // Session error causes.
    static var BYE                      = 'Terminated';
    static var WEBRTC_ERROR             = 'WebRTC Error';
    static var CANCELED                 = 'Canceled';
    static var NO_ANSWER                = 'No Answer';
    static var EXPIRES                  = 'Expires';
    static var NO_ACK                   = 'No ACK';
    static var DIALOG_ERROR             = 'Dialog Error';
    static var USER_DENIED_MEDIA_ACCESS = 'User Denied Media Access';
    static var BAD_MEDIA_DESCRIPTION    = 'Bad Media Description';
    static var RTP_TIMEOUT              = 'RTP Timeout';
}
  var SIP_ERROR_CAUSES = {
    Causes.REDIRECTED           : [ 300, 301, 302, 305, 380 ],
    Causes.BUSY                 : [ 486, 600 ],
    Causes.REJECTED             : [ 403, 603 ],
    Causes.NOT_FOUND            : [ 404, 604 ],
    Causes.UNAVAILABLE          : [ 480, 410, 408, 430 ],
    Causes.ADDRESS_INCOMPLETE   : [ 484, 424 ],
    Causes.INCOMPATIBLE_SDP     : [ 488, 606 ],
    Causes.AUTHENTICATION_ERROR : [ 401, 407 ]
  };

  var causes = {
    'CONNECTION_ERROR': Causes.CONNECTION_ERROR,
    'REQUEST_TIMEOUT': Causes.REQUEST_TIMEOUT,
    'SIP_FAILURE_CODE': Causes.SIP_FAILURE_CODE,
    'INTERNAL_ERROR': Causes.INTERNAL_ERROR,

    // SIP error causes.
    'BUSY': Causes.BUSY,
    'REJECTED ': Causes.REJECTED,
    'REDIRECTED': Causes.REDIRECTED,
    'UNAVAILABLE': Causes.UNAVAILABLE,
    'NOT_FOUND': Causes.NOT_FOUND,
    'ADDRESS_INCOMPLETE': Causes.ADDRESS_INCOMPLETE,
    'INCOMPATIBLE_SDP': Causes.INCOMPATIBLE_SDP,
    'MISSING_SDP': Causes.MISSING_SDP,
    'AUTHENTICATION_ERROR': Causes.AUTHENTICATION_ERROR,

    // Session error causes.
    'BYE': Causes.BYE,
    'WEBRTC_ERROR': Causes.WEBRTC_ERROR,
    'CANCELED': Causes.CANCELED,
    'NO_ANSWER': Causes.NO_ANSWER,
    'EXPIRES': Causes.EXPIRES,
    'NO_ACK': Causes.NO_ACK,
    'DIALOG_ERROR': Causes.DIALOG_ERROR,
    'USER_DENIED_MEDIA_ACCESS': Causes.USER_DENIED_MEDIA_ACCESS,
    'BAD_MEDIA_DESCRIPTION': Causes.BAD_MEDIA_DESCRIPTION,
    'RTP_TIMEOUT': Causes.RTP_TIMEOUT,
  };

  // SIP Methods.
  var ACK       = 'ACK';
  var BYE       = 'BYE';
  var CANCEL    = 'CANCEL';
  var INFO      = 'INFO';
  var INVITE    = 'INVITE';
  var MESSAGE   = 'MESSAGE';
  var NOTIFY    = 'NOTIFY';
  var OPTIONS   = 'OPTIONS';
  var REGISTER  = 'REGISTER';
  var REFER     = 'REFER';
  var UPDATE    = 'UPDATE';
  var SUBSCRIBE = 'SUBSCRIBE';

  /* SIP Response Reasons
   * DOC: https://www.iana.org/assignments/sip-parameters
   * Copied from https://github.com/versatica/OverSIP/blob/master/lib/oversip/sip/constants.rb#L7
   */
  var REASON_PHRASE = {
    100 : 'Trying',
    180 : 'Ringing',
    181 : 'Call Is Being Forwarded',
    182 : 'Queued',
    183 : 'Session Progress',
    199 : 'Early Dialog Terminated', // draft-ietf-sipcore-199
    200 : 'OK',
    202 : 'Accepted', // RFC 3265
    204 : 'No Notification', // RFC 5839
    300 : 'Multiple Choices',
    301 : 'Moved Permanently',
    302 : 'Moved Temporarily',
    305 : 'Use Proxy',
    380 : 'Alternative Service',
    400 : 'Bad Request',
    401 : 'Unauthorized',
    402 : 'Payment Required',
    403 : 'Forbidden',
    404 : 'Not Found',
    405 : 'Method Not Allowed',
    406 : 'Not Acceptable',
    407 : 'Proxy Authentication Required',
    408 : 'Request Timeout',
    410 : 'Gone',
    412 : 'Conditional Request Failed', // RFC 3903
    413 : 'Request Entity Too Large',
    414 : 'Request-URI Too Long',
    415 : 'Unsupported Media Type',
    416 : 'Unsupported URI Scheme',
    417 : 'Unknown Resource-Priority', // RFC 4412
    420 : 'Bad Extension',
    421 : 'Extension Required',
    422 : 'Session Interval Too Small', // RFC 4028
    423 : 'Interval Too Brief',
    424 : 'Bad Location Information', // RFC 6442
    428 : 'Use Identity Header', // RFC 4474
    429 : 'Provide Referrer Identity', // RFC 3892
    430 : 'Flow Failed', // RFC 5626
    433 : 'Anonymity Disallowed', // RFC 5079
    436 : 'Bad Identity-Info', // RFC 4474
    437 : 'Unsupported Certificate', // RFC 4744
    438 : 'Invalid Identity Header', // RFC 4744
    439 : 'First Hop Lacks Outbound Support', // RFC 5626
    440 : 'Max-Breadth Exceeded', // RFC 5393
    469 : 'Bad Info Package', // draft-ietf-sipcore-info-events
    470 : 'Consent Needed', // RFC 5360
    478 : 'Unresolvable Destination', // Custom code copied from Kamailio.
    480 : 'Temporarily Unavailable',
    481 : 'Call/Transaction Does Not Exist',
    482 : 'Loop Detected',
    483 : 'Too Many Hops',
    484 : 'Address Incomplete',
    485 : 'Ambiguous',
    486 : 'Busy Here',
    487 : 'Request Terminated',
    488 : 'Not Acceptable Here',
    489 : 'Bad Event', // RFC 3265
    491 : 'Request Pending',
    493 : 'Undecipherable',
    494 : 'Security Agreement Required', // RFC 3329
    500 : 'JsSIP Internal Error',
    501 : 'Not Implemented',
    502 : 'Bad Gateway',
    503 : 'Service Unavailable',
    504 : 'Server Time-out',
    505 : 'Version Not Supported',
    513 : 'Message Too Large',
    580 : 'Precondition Failure', // RFC 3312
    600 : 'Busy Everywhere',
    603 : 'Decline',
    604 : 'Does Not Exist Anywhere',
    606 : 'Not Acceptable'
  };

 var ALLOWED_METHODS     = 'INVITE,ACK,CANCEL,BYE,UPDATE,MESSAGE,OPTIONS,REFER,INFO';
 var ACCEPTED_BODY_TYPES = 'application/sdp, application/dtmf-relay';
 var MAX_FORWARDS        = 69;
 var SESSION_EXPIRES     = 90;
 var MIN_SESSION_EXPIRES = 60;
