import '../../sip_ua.dart';
import '../SIPMessage.dart';
import '../Transport.dart';
import '../UA.dart';
import '../event_manager/event_manager.dart';

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

abstract class TransactionBase extends EventManager {
  String id;
  UA ua;
  Transport transport;
  TransactionState state;
  IncomingMessage last_response;
  var request;
  void onTransportError();

  void send();

  void receiveResponse(int status_code, IncomingMessage response,
      [void Function() onSuccess, void Function() onFailure]) {
    // default NO_OP implementation
  }
}
