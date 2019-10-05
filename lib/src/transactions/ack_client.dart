import 'package:sip_ua/sip_ua.dart';
import 'package:sip_ua/src/Transport.dart';
import 'package:sip_ua/src/Utils.dart';
import 'package:sip_ua/src/transactions/Transactions.dart';
import 'package:sip_ua/src/transactions/transaction_base.dart';

final act_logger = new Logger('AckClientTransaction');
debugact(msg) => act_logger.debug(msg);

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
    debugact('transport error occurred for transaction ${this.id}');
    this.eventHandlers['onTransportError']();
  }
}

