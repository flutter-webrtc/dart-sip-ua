class C {
  // RTCSession states.
  static const STATUS_NULL = 0;
  static const STATUS_INVITE_SENT = 1;
  static const STATUS_1XX_RECEIVED = 2;
  static const STATUS_INVITE_RECEIVED = 3;
  static const STATUS_WAITING_FOR_ANSWER = 4;
  static const STATUS_ANSWERED = 5;
  static const STATUS_WAITING_FOR_ACK = 6;
  static const STATUS_CANCELED = 7;
  static const STATUS_TERMINATED = 8;
  static const STATUS_CONFIRMED = 9;
}

abstract class MediaSession {
  var _ua;
  MediaSession(this._ua);

  connect(target, options);

}

class MediaSessionFactory {

  static MediaSession createRTCSession(ua){
    return null;
  }
  static supportWebRTC() {
    return true;
  }

}
