import 'dart:async';

class Timers {
  static const int T1 = 500;
  static const int T2 = 4000;
  static const int T4 = 5000;
  static const int TIMER_B = 64 * T1;
  static const int TIMER_D = 0 * T1;
  static const int TIMER_F = 64 * T1;
  static const int TIMER_H = 64 * T1;
  static const int TIMER_I = 0 * T1;
  static const int TIMER_J = 0 * T1;
  static const int TIMER_K = 0 * T4;
  static const int TIMER_L = 64 * T1;
  static const int TIMER_M = 64 * T1;
  static const int PROVISIONAL_RESPONSE_INTERVAL =
      60000; // See RFC 3261 Section 13.3.1.1
}

Timer setTimeout(Function fn, int duration) {
  return Timer(Duration(milliseconds: duration), fn as void Function());
}

void clearTimeout(Timer? timer) {
  if (timer != null) {
    timer.cancel();
  }
}

Timer setInterval(Function fn, int interval) {
  return Timer.periodic(Duration(milliseconds: interval), (Timer timer) {
    fn();
  });
}

void clearInterval(Timer? timer) {
  if (timer != null) {
    timer.cancel();
  }
}
