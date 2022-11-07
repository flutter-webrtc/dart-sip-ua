import 'package:sip_ua/src/sip_message.dart';
import '../constants.dart';
import '../timers.dart';
import 'invite_server.dart';
import 'non_invite_server.dart';
import 'transaction_base.dart';

class TransactionBag {
  Map<String, TransactionBase> transactions = <String, TransactionBase>{};

  int countTransactions() {
    return transactions.length;
  }

  String _buildKey(Type type, String id) {
    return '$type:$id';
  }

  void addTransaction(TransactionBase transaction) {
    String key = _buildKey(transaction.runtimeType, transaction.id!);
    transactions[key] = transaction;
  }

  void removeTransaction(TransactionBase transaction) {
    String key = _buildKey(transaction.runtimeType, transaction.id!);
    transactions.remove(key);
  }

  List<T> getAll<T>(Type type) {
    List<T> results = <T>[];

    for (TransactionBase transaction in transactions.values) {
      if (transaction.runtimeType == type) {
        results.add(transaction as T);
      }
    }

    return results;
  }

  T? getTransaction<T>(Type type, String id) {
    String key = _buildKey(type, id);
    return transactions[key] as T?;
  }

  List<TransactionBase> removeAll() {
    List<TransactionBase> list = <TransactionBase>[];
    list.addAll(transactions.values);
    transactions.clear();
    return list;
  }
}

/**
 * INVITE:
 *  _true_ if retransmission
 *  _false_ request
 *
 * ACK:
 *  _true_  ACK to non2xx response
 *  _false_ ACK must be passed to TU (accepted state)
 *          ACK to 2xx response
 *
 * CANCEL:
 *  _true_  no matching invite transaction
 *  _false_ matching invite transaction and no final response sent
 *
 * OTHER:
 *  _true_  retransmission
 *  _false_ request
 */
bool checkTransaction(TransactionBag transactions, IncomingRequest request) {
  switch (request.method) {
    case SipMethod.INVITE:
      InviteServerTransaction? tr = transactions.getTransaction(
          InviteServerTransaction, request.via_branch!);
      if (tr != null) {
        switch (tr.state) {
          case TransactionState.PROCEEDING:
            tr.transport!.send(tr.last_response);
            break;

          // RFC 6026 7.1 Invite retransmission.
          // Received while in TransactionState.ACCEPTED state. Absorb it.
          case TransactionState.ACCEPTED:
            break;
          default:
            break;
        }

        return true;
      }
      break;
    case SipMethod.ACK:
      InviteServerTransaction? tr = transactions.getTransaction(
          InviteServerTransaction, request.via_branch!);

      // RFC 6026 7.1.
      if (tr != null) {
        if (tr.state == TransactionState.ACCEPTED) {
          return false;
        } else if (tr.state == TransactionState.COMPLETED) {
          tr.state = TransactionState.CONFIRMED;
          tr.I = setTimeout(() {
            tr.timer_I();
          }, Timers.TIMER_I);

          return true;
        }
      }
      // ACK to 2XX Response.
      else {
        return false;
      }
      break;
    case SipMethod.CANCEL:
      InviteServerTransaction? tr = transactions.getTransaction(
          InviteServerTransaction, request.via_branch!);
      if (tr != null) {
        request.reply_sl(200);
        if (tr.state == TransactionState.PROCEEDING) {
          return false;
        } else {
          return true;
        }
      } else {
        request.reply_sl(481);
        return true;
      }
    default:
      // Non-INVITE Server Transaction RFC 3261 17.2.2.
      NonInviteServerTransaction? tr = transactions.getTransaction(
          NonInviteServerTransaction, request.via_branch!);
      if (tr != null) {
        switch (tr.state) {
          case TransactionState.TRYING:
            break;
          case TransactionState.PROCEEDING:
          case TransactionState.COMPLETED:
            tr.transport!.send(tr.last_response);
            break;
          default:
            break;
        }

        return true;
      }
      break;
  }
  return false;
}
