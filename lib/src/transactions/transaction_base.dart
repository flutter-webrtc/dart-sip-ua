import '../event_manager/event_manager.dart';
import '../sip_message.dart';
import '../transport.dart';
import '../ua.dart';

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
  String? id;
  late UA ua;
  Transport? transport;
  TransactionState? state;
  IncomingMessage? last_response;
  dynamic request;
  void onTransportError();

  void send();

  void receiveResponse(int status_code, IncomingMessage response,
      [void Function()? onSuccess, void Function()? onFailure]) {
    // default NO_OP implementation
  }
}
