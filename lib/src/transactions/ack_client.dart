import '../../sip_ua.dart';
import '../transport.dart';
import '../ua.dart';
import '../utils.dart';
import '../event_manager/event_manager.dart';
import '../event_manager/internal_events.dart';
import '../logger.dart';
import 'transaction_base.dart';

final act_logger = new Log();

class AckClientTransaction extends TransactionBase {
  var eventHandlers;

  AckClientTransaction(UA ua, Transport transport, request, eventHandlers) {
    this.id = 'z9hG4bK${Math.floor(Math.random() * 10000000)}';
    this.transport = transport;
    this.request = request;
    this.eventHandlers = eventHandlers;

    var via = 'SIP/2.0/${transport.via_transport}';

    via += ' ${ua.configuration.via_host};branch=${this.id}';

    this.request.setHeader('via', via);
  }

  send() {
    if (!this.transport.send(this.request)) {
      this.onTransportError();
    }
  }

  onTransportError() {
    logger.debug('transport error occurred for transaction ${this.id}');
    this.eventHandlers.emit(EventOnTransportError());
  }
}
