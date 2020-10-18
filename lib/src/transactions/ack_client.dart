import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../logger.dart';
import '../transport.dart';
import '../ua.dart';
import '../utils.dart';
import 'transaction_base.dart';

class AckClientTransaction extends TransactionBase {
  AckClientTransaction(
      UA ua, Transport transport, request, EventManager eventHandlers) {
    this.id = 'z9hG4bK${Math.floor(Math.random() * 10000000)}';
    this.transport = transport;
    this.request = request;
    this._eventHandlers = eventHandlers;

    var via = 'SIP/2.0/${transport.via_transport}';

    via += ' ${ua.configuration.via_host};branch=${this.id}';

    this.request.setHeader('via', via);
  }

  EventManager _eventHandlers;

  @override
  void send() {
    if (!this.transport.send(this.request)) {
      this.onTransportError();
    }
  }

  @override
  void onTransportError() {
    logger.debug('transport error occurred for transaction ${this.id}');
    this._eventHandlers.emit(EventOnTransportError());
  }
}
