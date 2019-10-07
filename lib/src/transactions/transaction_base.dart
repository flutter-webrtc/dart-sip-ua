import 'package:events2/events2.dart';

import '../../sip_ua.dart';
import '../Transport.dart';

enum TransactionState {
  // Transaction states.
  TRYING,
  PROCEEDING,
  CALLING,
  ACCEPTED,
  COMPLETED,
  TERMINATED,
  CONFIRMED
}

abstract class TransactionBase extends EventEmitter {
  String id;
  UA ua;
  Transport transport;
  TransactionState state;
  var last_response;
  var request;
  void onTransportError();

  void send();
}
