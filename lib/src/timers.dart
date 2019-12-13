import 'dart:async';

class Timers {
  static const T1 = 500;
  static const T2 = 4000;
  static const T4 = 5000;
  static const TIMER_B = 64 * T1;
  static const TIMER_D = 0 * T1;
  static const TIMER_F = 64 * T1;
  static const TIMER_H = 64 * T1;
  static const TIMER_I = 0 * T1;
  static const TIMER_J = 0 * T1;
  static const TIMER_K = 0 * T4;
  static const TIMER_L = 64 * T1;
  static const TIMER_M = 64 * T1;
  static const PROVISIONAL_RESPONSE_INTERVAL =
      60000; // See RFC 3261 Section 13.3.1.1
}

Timer setTimeout(fn, duration) {
  return new Timer(new Duration(milliseconds: duration), fn);
}

clearTimeout(Timer timer) {
  if (timer != null) timer.cancel();
}

Timer setInterval(fn, interval) {
  return new Timer.periodic(new Duration(milliseconds: interval),
      (Timer timer) {
    fn();
  });
}

clearInterval(Timer timer) {
  if (timer != null) timer.cancel();
}
