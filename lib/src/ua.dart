import 'dart:async';

import 'config.dart' as config;
import 'config.dart';
import 'constants.dart' as DartSIP_C;
import 'constants.dart';
import 'data.dart';
import 'dialog.dart';
import 'event_manager/event_manager.dart';
import 'event_manager/internal_events.dart';
import 'exceptions.dart' as Exceptions;
import 'logger.dart';
import 'message.dart';
import 'options.dart';
import 'parser.dart' as Parser;
import 'registrator.dart';
import 'rtc_session.dart';
import 'sanity_check.dart';
import 'sip_message.dart';
import 'subscriber.dart';
import 'timers.dart';
import 'transactions/invite_client.dart';
import 'transactions/invite_server.dart';
import 'transactions/non_invite_client.dart';
import 'transactions/non_invite_server.dart';
import 'transactions/transaction_base.dart';
import 'transactions/transactions.dart';
import 'transport.dart';
import 'transports/websocket_interface.dart';
import 'uri.dart';
import 'utils.dart' as Utils;

class C {
  // UA status codes.
  static const int STATUS_INIT = 0;
  static const int STATUS_READY = 1;
  static const int STATUS_USER_CLOSED = 2;
  static const int STATUS_NOT_READY = 3;

  // UA error codes.
  static const int CONFIGURATION_ERROR = 1;
  static const int NETWORK_ERROR = 2;
}

// TODO(Perondas): Figure out what this is
final bool hasRTCPeerConnection = true;

class DynamicSettings {
  bool? register = false;
}

class Contact {
  Contact(this.uri);

  String? pub_gruu;
  String? temp_gruu;
  bool anonymous = false;
  bool outbound = false;
  URI? uri;

  @override
  String toString() {
    String contact = '<';

    if (anonymous) {
      contact += temp_gruu ?? 'sip:anonymous@anonymous.invalid;transport=ws';
    } else {
      contact += pub_gruu ?? uri.toString();
    }

    if (outbound && (anonymous ? temp_gruu == null : pub_gruu == null)) {
      contact += ';ob';
    }

    contact += '>';
    return contact;
  }
}

/**
 * The User-Agent class.
 * @class DartSIP.UA
 * @param {Object} configuration Configuration parameters.
 * @throws {DartSIP.Exceptions.ConfigurationError} If a configuration parameter is invalid.
 * @throws {TypeError} If no configuration is given.
 */
class UA extends EventManager {
  UA(Settings configuration) {
    logger.d('new() [configuration:${configuration.toString()}]');
    // Load configuration.
    try {
      _loadConfig(configuration);
    } catch (e) {
      _status = C.STATUS_NOT_READY;
      _error = C.CONFIGURATION_ERROR;
      throw e;
    }

    // Initialize registrator.
    _registrator = Registrator(this);
  }

  final Map<String?, Subscriber> _subscribers = <String?, Subscriber>{};
  final Map<String, dynamic> _cache = <String, dynamic>{
    'credentials': <dynamic>{}
  };

  final Settings _configuration = Settings();
  DynamicSettings? _dynConfiguration = DynamicSettings();

  final Map<String, Dialog> _dialogs = <String, Dialog>{};

  // User actions outside any session/dialog (MESSAGE/OPTIONS).
  final Set<Applicant> _applicants = <Applicant>{};

  final Map<String?, RTCSession> _sessions = <String?, RTCSession>{};
  Transport? _transport;
  Contact? _contact;
  int _status = C.STATUS_INIT;
  int? _error;
  final TransactionBag _transactions = TransactionBag();

// Custom UA empty object for high level use.
  final Map<String, dynamic> _data = <String, dynamic>{};

  Timer? _closeTimer;
  late Registrator _registrator;

  int get status => _status;

  Contact? get contact => _contact;

  Settings get configuration => _configuration;

  Transport? get transport => _transport;

  TransactionBag get transactions => _transactions;

  // Flag that indicates whether UA is currently stopping
  bool _stopping = false;

  // ============
  //  High Level API
  // ============

  /**
   * Connect to the server if status = STATUS_INIT.
   * Resume UA after being closed.
   */
  void start() {
    logger.d('start()');

    if (_status == C.STATUS_INIT) {
      _transport!.connect();
    } else if (_status == C.STATUS_USER_CLOSED) {
      logger.d('restarting UA');

      // Disconnect.
      if (_closeTimer != null) {
        clearTimeout(_closeTimer);
        _closeTimer = null;
        _transport!.disconnect();
      }

      // Reconnect.
      _status = C.STATUS_INIT;
      _transport!.connect();
    } else if (_status == C.STATUS_READY) {
      logger.d('UA is in READY status, not restarted');
    } else {
      logger.d(
          'ERROR: connection is down, Auto-Recovery system is trying to reconnect');
    }

    // Set dynamic configuration.
    _dynConfiguration!.register = _configuration.register;
  }

  /**
   * Register.
   */
  void register() {
    logger.d('register()');
    _dynConfiguration!.register = true;
    _registrator.register();
  }

  /**
   * Unregister.
   */
  void unregister({bool all = false}) {
    logger.d('unregister()');

    _dynConfiguration!.register = false;
    _registrator.unregister(all);
  }

  /**
   * Create subscriber instance
   */
  Subscriber subscribe(
    String target,
    String eventName,
    String accept, [
    int expires = 900,
    String? contentType,
    String? allowEvents,
    Map<String, dynamic> requestParams = const <String, dynamic>{},
    List<String> extraHeaders = const <String>[],
  ]) {
    logger.d('subscribe()');

    return Subscriber(this, target, eventName, accept, expires, contentType,
        allowEvents, requestParams, extraHeaders);
  }

  /**
   * Get the Registrator instance.
   */
  Registrator? registrator() {
    return _registrator;
  }

  /**
   * Registration state.
   */
  bool isRegistered() {
    return _registrator.registered;
  }

  /**
   * Connection state.
   */
  bool isConnected() {
    return _transport!.isConnected();
  }

  /**
   * Make an outgoing call.
   *
   * -param {String} target
   * -param {Object} [options]
   *
   * -throws {TypeError}
   *
   */
  RTCSession call(String target, Map<String, dynamic> options) {
    logger.d('call()');
    RTCSession session = RTCSession(this);
    session.connect(target, options);
    return session;
  }

  /**
   * Send a message.
   *
   * -param {String} target
   * -param {String} body
   * -param {Object} [options]
   *
   * -throws {TypeError}
   *
   */
  Message sendMessage(String target, String body, Map<String, dynamic>? options,
      Map<String, dynamic>? params) {
    logger.d('sendMessage()');
    Message message = Message(this);
    message.send(target, body, options, params);
    return message;
  }

  /**
   * Send a Options.
   *
   * -param {String} target
   * -param {String} body
   * -param {Object} [options]
   *
   * -throws {TypeError}
   *
   */
  Options sendOptions(
      String target, String body, Map<String, dynamic>? options) {
    logger.d('sendOptions()');
    Options message = Options(this);
    message.send(target, body, options);
    return message;
  }

  /**
   * Terminate ongoing sessions.
   */
  void terminateSessions(Map<String, dynamic> options) {
    logger.d('terminateSessions()');
    _sessions.forEach((String? key, _) {
      if (!_sessions[key]!.isEnded()) {
        _sessions[key]!.terminate(options);
      }
    });
  }

  /**
   * Gracefully close.
   *
   */
  void stop() {
    logger.d('stop()');

    // Remove dynamic settings.
    _dynConfiguration = null;

    if (_status == C.STATUS_USER_CLOSED) {
      logger.d('UA already closed');

      return;
    }

    // Close registrator.
    _registrator.close();

    // If there are session wait a bit so CANCEL/BYE can be sent and their responses received.
    int num_sessions = _sessions.length;

    // Run  _terminate_ on every Session.
    _sessions.forEach((String? key, _) {
      if (_sessions.containsKey(key)) {
        logger.d('closing session $key');
        try {
          RTCSession rtcSession = _sessions[key]!;
          if (!rtcSession.isEnded()) {
            rtcSession.terminate();
          }
        } catch (error, s) {
          logger.e(error.toString(), null, s);
        }
      }
    });

    // Run _terminate on ever subscription
    _subscribers.forEach((String? key, _) {
      if (_subscribers.containsKey(key)) {
        logger.d('closing subscription $key');
        try {
          Subscriber subscriber = _subscribers[key]!;
          subscriber.terminate(null);
        } catch (error, s) {
          logger.e(error.toString(), null, s);
        }
      }
    });

    _stopping = true;

    // Run  _close_ on every applicant.
    for (Applicant applicant in _applicants) {
      try {
        applicant.close();
      } catch (error) {}
    }

    _status = C.STATUS_USER_CLOSED;

    int num_transactions = _transactions.countTransactions();
    if (num_transactions == 0 && num_sessions == 0) {
      _transport!.disconnect();
    } else {
      _closeTimer = setTimeout(() {
        logger.i('Closing connection');
        _closeTimer = null;
        _transport!.disconnect();
      }, 2000);
    }
  }

  /**
   * Normalice a string into a valid SIP request URI
   * -param {String} target
   * -returns {DartSIP.URI|null}
   */
  URI? normalizeTarget(String? target) {
    return Utils.normalizeTarget(target, _configuration.hostport_params);
  }

  /**
   * Allow retrieving configuration and autogenerated fields in runtime.
   */
  String? get(String parameter) {
    switch (parameter) {
      case 'realm':
        return _configuration.realm;

      case 'ha1':
        return _configuration.ha1;

      default:
        logger.e('get() | cannot get "$parameter" parameter in runtime');

        return null;
    }
  }

  /**
   * Allow configuration changes in runtime.
   * Returns true if the parameter could be set.
   */
  bool set(String parameter, dynamic value) {
    switch (parameter) {
      case 'password':
        {
          _configuration.password = value.toString();
          break;
        }

      case 'realm':
        {
          _configuration.realm = value.toString();
          break;
        }

      case 'ha1':
        {
          _configuration.ha1 = value.toString();
          // Delete the plain SIP password.
          _configuration.password = null;
          break;
        }

      case 'display_name':
        {
          _configuration.display_name = value;
          break;
        }

      default:
        logger.e('set() | cannot set "$parameter" parameter in runtime');

        return false;
    }

    return true;
  }

  // ==================
  // Event Handlers.
  // ==================

  /**
   * Transaction
   */
  void newTransaction(TransactionBase transaction) {
    _transactions.addTransaction(transaction);
    emit(EventNewTransaction(transaction: transaction));
  }

  /**
   * Transaction destroyed.
   */
  void destroyTransaction(TransactionBase transaction) {
    _transactions.removeTransaction(transaction);
    emit(EventTransactionDestroyed(transaction: transaction));
  }

  /**
   * Subscriber
   */
  void newSubscriber({required Subscriber sub}) {
    _subscribers[sub.id] = sub;
  }

  /**
   * Subscriber destroyed.
   */
  void destroySubscriber(Subscriber sub) {
    _subscribers.remove(sub.id);
  }

  /**
   * Dialog
   */
  void newDialog(Dialog dialog) {
    _dialogs[dialog.id.toString()] = dialog;
  }

  /**
   * Dialog destroyed.
   */
  void destroyDialog(Dialog dialog) {
    _dialogs.remove(dialog.id.toString());
  }

  /**
   *  Message
   */
  void newMessage(Message message, String originator, dynamic request) {
    if (_stopping) {
      return;
    }
    _applicants.add(message);
    emit(EventNewMessage(
        message: message, originator: originator, request: request));
  }

  /**
   *  Options
   */
  void newOptions(Options message, String originator, dynamic request) {
    if (_stopping) {
      return;
    }
    _applicants.add(message);

    emit(EventNewOptions(
        message: message, originator: originator, request: request));
  }

  /**
   *  Message destroyed.
   */
  void destroyMessage(Message message) {
    if (_stopping) {
      return;
    }
    _applicants.remove(message);
  }

  /**
   *  Options destroyed.
   */
  void destroyOptions(Options message) {
    if (_stopping) {
      return;
    }
    _applicants.remove(message);
  }

  /**
   * RTCSession
   */
  void newRTCSession(
      {required RTCSession session, String? originator, dynamic request}) {
    _sessions[session.id] = session;
    emit(EventNewRTCSession(
        session: session, originator: originator, request: request));
  }

  /**
   * RTCSession destroyed.
   */
  void destroyRTCSession(RTCSession session) {
    _sessions.remove(session.id);
  }

  /**
   * Registered
   */
  void registered({required dynamic response}) {
    emit(EventRegistered(
        cause: ErrorCause(
            cause: 'registered',
            status_code: response.status_code,
            reason_phrase: response.reason_phrase)));
  }

  /**
   * Unregistered
   */
  void unregistered({dynamic response, String? cause}) {
    emit(EventUnregister(
        cause: ErrorCause(
            cause: cause ?? 'unregistered',
            status_code: response?.status_code ?? 0,
            reason_phrase: response?.reason_phrase ?? '')));
  }

  /**
   * Registration Failed
   */
  void registrationFailed({required dynamic response, String? cause}) {
    emit(EventRegistrationFailed(
        cause: ErrorCause(
            cause: Utils.sipErrorCause(response.status_code),
            status_code: response.status_code,
            reason_phrase: response.reason_phrase)));
  }

  // =================
  // ReceiveRequest.
  // =================

  /**
   * Request reception
   */
  void receiveRequest(IncomingRequest request) {
    DartSIP_C.SipMethod? method = request.method;

    // Check that request URI points to us.
    if (request.ruri!.user != _configuration.uri.user &&
        request.ruri!.user != _contact!.uri!.user) {
      logger.d('Request-URI does not point to us');
      if (request.method != SipMethod.ACK) {
        request.reply_sl(404);
      }

      return;
    }

    // Check request URI scheme.
    if (request.ruri!.scheme == DartSIP_C.SIPS) {
      request.reply_sl(416);

      return;
    }

    // Check transaction.
    if (checkTransaction(_transactions, request)) {
      return;
    }

    // Create the server transaction.
    if (method == SipMethod.INVITE) {
      /* eslint-disable no-*/
      InviteServerTransaction(this, _transport, request);
      /* eslint-enable no-*/
    } else if (method != SipMethod.ACK && method != SipMethod.CANCEL) {
      /* eslint-disable no-*/
      NonInviteServerTransaction(this, _transport, request);
      /* eslint-enable no-*/
    }

    /* RFC3261 12.2.2
     * Requests that do not change in any way the state of a dialog may be
     * received within a dialog (for example, an OPTIONS request).
     * They are processed as if they had been received outside the dialog.
     */
    if (method == SipMethod.OPTIONS) {
      if (!hasListeners(EventNewOptions())) {
        request.reply(200);
        return;
      }
      Options message = Options(this);
      message.init_incoming(request);
      return;
    } else if (method == SipMethod.MESSAGE) {
      if (!hasListeners(EventNewMessage())) {
        request.reply(405);
        return;
      }
      Message message = Message(this);
      message.init_incoming(request);
      return;
    } else if (method == SipMethod.INVITE) {
      // Initial INVITE.
      if (request.to_tag != null && !hasListeners(EventNewRTCSession())) {
        request.reply(405);

        return;
      }
    } else if (method == SipMethod.SUBSCRIBE) {
      if (listeners['newSubscribe']?.length == 0) {
        request.reply(405);

        return;
      }
    }

    Dialog? dialog;
    RTCSession? session;

    // Initial Request.
    if (request.to_tag == null) {
      switch (method) {
        case SipMethod.INVITE:
          if (hasRTCPeerConnection) {
            if (request.hasHeader('replaces')) {
              ParsedData replaces = request.replaces;

              dialog = _findDialog(
                  replaces.call_id, replaces.from_tag!, replaces.to_tag!);
              if (dialog != null) {
                session = dialog.owner as RTCSession?;
                if (!session!.isEnded()) {
                  session.receiveRequest(request);
                } else {
                  request.reply(603);
                }
              } else {
                request.reply(481);
              }
            } else {
              session = RTCSession(this);
              session.init_incoming(request);
            }
          } else {
            logger.e('INVITE received but WebRTC is not supported');
            request.reply(488);
          }
          break;
        case SipMethod.BYE:
          // Out of dialog BYE received.
          request.reply(481);
          break;
        case SipMethod.CANCEL:
          session =
              _findSession(request.call_id!, request.from_tag, request.to_tag);
          if (session != null) {
            session.receiveRequest(request);
          } else {
            logger.d('received CANCEL request for a non existent session');
          }
          break;
        case SipMethod.ACK:
          /* Absorb it.
           * ACK request without a corresponding Invite Transaction
           * and without To tag.
           */
          break;
        case SipMethod.NOTIFY:
          // Receive sip event.
          emit(EventSipEvent(request: request));
          request.reply(200);
          break;
        case SipMethod.SUBSCRIBE:
          emit(EventOnNewSubscribe(request: request));
          break;
        default:
          request.reply(405);
          break;
      }
    }
    // In-dialog request.
    else {
      dialog =
          _findDialog(request.call_id!, request.from_tag!, request.to_tag!);

      if (dialog != null) {
        dialog.receiveRequest(request);
      } else if (method == SipMethod.NOTIFY) {
        Subscriber? sub = _findSubscriber(
            request.call_id!, request.from_tag!, request.to_tag!);
        if (sub != null) {
          sub.receiveRequest(request);
        } else {
          logger.d('received NOTIFY request for a non existent subscription');
          request.reply(481, 'Subscription does not exist');
        }
      }

      /* RFC3261 12.2.2
       * Request with to tag, but no matching dialog found.
       * Exception: ACK for an Invite request for which a dialog has not
       * been created.
       */
      else if (method != SipMethod.ACK) {
        request.reply(481);
      }
    }
  }

  // ============
  // Utils.
  // ============

  Subscriber? _findSubscriber(String call_id, String from_tag, String to_tag) {
    String id = call_id;
    Subscriber? sub = _subscribers[id];

    return sub;
  }

  /**
   * Get the session to which the request belongs to, if any.
   */
  RTCSession? _findSession(String call_id, String? from_tag, String? to_tag) {
    String sessionIDa = call_id + (from_tag ?? '');
    RTCSession? sessionA = _sessions[sessionIDa];
    String sessionIDb = call_id + (to_tag ?? '');
    RTCSession? sessionB = _sessions[sessionIDb];

    if (sessionA != null) {
      return sessionA;
    } else if (sessionB != null) {
      return sessionB;
    } else {
      return null;
    }
  }

  /**
   * Get the dialog to which the request belongs to, if any.
   */
  Dialog? _findDialog(String call_id, String from_tag, String to_tag) {
    String id = call_id + from_tag + to_tag;
    Dialog? dialog = _dialogs[id];

    if (dialog != null) {
      return dialog;
    } else {
      id = call_id + to_tag + from_tag;
      dialog = _dialogs[id];
      if (dialog != null) {
        return dialog;
      } else {
        return null;
      }
    }
  }

  void _loadConfig(Settings configuration) {
    // Check and load the given configuration.
    try {
      config.load(configuration, _configuration);
    } catch (e) {
      throw e;
    }

    // Post Configuration Process.

    // Allow passing 0 number as display_name.
    if (_configuration.display_name is num &&
        (_configuration.display_name as num?) == 0) {
      _configuration.display_name = '0';
    }

    // Instance-id for GRUU.
    _configuration.instance_id ??= Utils.newUUID();

    // Jssip_id instance parameter. Static random tag of length 5.
    _configuration.jssip_id = Utils.createRandomToken(5);

    // String containing _configuration.uri without scheme and user.
    URI hostport_params = _configuration.uri.clone();

    hostport_params.user = null;
    _configuration.hostport_params = hostport_params
        .toString()
        .replaceAll(RegExp(r'sip:', caseSensitive: false), '');

    // Transport.
    try {
      _transport = Transport(_configuration.sockets!, <String, int>{
        // Recovery options.
        'max_interval': _configuration.connection_recovery_max_interval,
        'min_interval': _configuration.connection_recovery_min_interval
      });

      // Transport event callbacks.
      _transport!.onconnecting = onTransportConnecting;
      _transport!.onconnect = onTransportConnect;
      _transport!.ondisconnect = onTransportDisconnect;
      _transport!.ondata = onTransportData;
    } catch (e) {
      logger.e('Failed to _loadConfig: ${e.toString()}');
      throw Exceptions.ConfigurationError('sockets', _configuration.sockets);
    }

    String transport = 'ws';

    if (_configuration.sockets!.isNotEmpty) {
      transport = _configuration.sockets!.first.via_transport.toLowerCase();
    }

    // Remove sockets instance from configuration object.
    // TODO(cloudwebrtc):  need dispose??
    _configuration.sockets = null;

    // Check whether authorization_user is explicitly defined.
    // Take '_configuration.uri.user' value if not.
    _configuration.authorization_user ??= _configuration.uri.user;

    // If no 'registrar_server' is set use the 'uri' value without user portion and
    // without URI params/headers.
    if (_configuration.registrar_server == null) {
      URI registrar_server = _configuration.uri.clone();
      registrar_server.user = null;
      registrar_server.clearParams();
      registrar_server.clearHeaders();
      _configuration.registrar_server = registrar_server;
    }

    // User no_answer_timeout.
    _configuration.no_answer_timeout *= 1000;

    // Via Host.
    if (_configuration.contact_uri != null) {
      _configuration.via_host = _configuration.contact_uri.host;
    }
    // Contact URI.
    else {
      _configuration.contact_uri = URI(
          'sip',
          Utils.createRandomToken(8),
          _configuration.via_host,
          null,
          <dynamic, dynamic>{'transport': transport});
    }
    _contact = Contact(_configuration.contact_uri);
    return;
  }

  /**
   * Transport event handlers
   */

// Transport connecting event.
  void onTransportConnecting(WebSocketInterface? socket, int? attempts) {
    logger.d('Transport connecting');
    emit(EventSocketConnecting(socket: socket));
  }

// Transport connected event.
  void onTransportConnect(Transport transport) {
    logger.d('Transport connected');
    if (_status == C.STATUS_USER_CLOSED) {
      return;
    }
    _status = C.STATUS_READY;
    _error = null;

    emit(EventSocketConnected(socket: transport.socket));

    if (_dynConfiguration!.register!) {
      _registrator.register();
    }
  }

// Transport disconnected event.
  void onTransportDisconnect(WebSocketInterface? socket, ErrorCause cause) {
    // Run _onTransportError_ callback on every client transaction using _transport_.
    _transactions.removeAll().forEach((TransactionBase transaction) {
      transaction.onTransportError();
    });

    emit(EventSocketDisconnected(socket: socket, cause: cause));

    // Call registrator _onTransportClosed_.
    _registrator.onTransportClosed();

    if (_status != C.STATUS_USER_CLOSED) {
      _status = C.STATUS_NOT_READY;
      _error = C.NETWORK_ERROR;
    }
  }

// Transport data event.
  void onTransportData(Transport transport, String messageData) {
    IncomingMessage? message = Parser.parseMessage(messageData, this);

    if (message == null) {
      return;
    }

    if (_status == C.STATUS_USER_CLOSED && message is IncomingRequest) {
      return;
    }

    // Do some sanity check.
    if (!sanityCheck(message, this, transport)) {
      return;
    }

    if (message is IncomingRequest) {
      message.transport = transport;
      receiveRequest(message);
    } else if (message is IncomingResponse) {
      /* Unike stated in 18.1.2, if a response does not match
    * any transaction, it is discarded here and no passed to the core
    * in order to be discarded there.
    */

      switch (message.method) {
        case SipMethod.INVITE:
          InviteClientTransaction? transaction = _transactions.getTransaction(
              InviteClientTransaction, message.via_branch!);
          if (transaction != null) {
            transaction.receiveResponse(message.status_code, message);
          }
          break;
        case SipMethod.ACK:
          // Just in case ;-).
          break;
        default:
          NonInviteClientTransaction? transaction = _transactions
              .getTransaction(NonInviteClientTransaction, message.via_branch!);
          if (transaction != null) {
            transaction.receiveResponse(message.status_code, message);
          }
          break;
      }
    }
  }
}

mixin Applicant {
  void close();
}
