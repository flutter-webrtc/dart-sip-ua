import '../sip_ua.dart';
import 'constants.dart' as DartSIP_C;
import 'constants.dart';
import 'exceptions.dart' as Exceptions;
import 'grammar.dart';
import 'logger.dart';
import 'transports/socket_interface.dart';
import 'transports/web_socket.dart';
import 'utils.dart' as Utils;

// Default settings.
class Settings {
  // SIP authentication.
  String? authorization_user;
  String? password;
  String? realm;
  String? ha1;

  // SIP account.
  String? display_name;
  URI? uri;
  URI? contact_uri;
  String user_agent = DartSIP_C.USER_AGENT;

  // SIP instance id (GRUU).
  String? instance_id = null;

  // Preloaded SIP Route header field.
  bool use_preloaded_route = false;

  // Session parameters.
  bool session_timers = true;
  SipMethod session_timers_refresh_method = SipMethod.UPDATE;
  int no_answer_timeout = 60;

  // Registration parameters.
  bool? register = true;
  int? register_expires = 600;
  dynamic registrar_server;
  List<String>? register_extra_headers;
  Map<String, dynamic>? register_extra_contact_uri_params;

  // Dtmf mode
  DtmfMode dtmf_mode = DtmfMode.INFO;

  TransportType? transportType;

  // Connection options.
  List<SIPUASocketInterface>? sockets = <SIPUASocketInterface>[];
  int connection_recovery_max_interval = 30;
  int connection_recovery_min_interval = 2;

  /*
   * Host address.
   * Value to be set in Via sent_by and host part of Contact FQDN.
  */
  String? via_host = '${Utils.createRandomToken(12)}.invalid';

  // DartSIP ID
  String? jssip_id;

  String? hostport_params;

  /// ICE Gathering Timeout (in millisecond).
  int ice_gathering_timeout = 500;

  bool terminateOnAudioMediaPortZero = false;

  /// Sip Message Delay (in millisecond) ( default 0 ).
  int sip_message_delay = 0;
}

// Configuration checks.
class Checks {
  Map<String, Null Function(Settings src, Settings? dst)> mandatory =
      <String, Null Function(Settings src, Settings? dst)>{
    'sockets': (Settings src, Settings? dst) {
      List<SIPUASocketInterface>? sockets = src.sockets;

      /* Allow defining sockets parameter as:
       *  Socket: socket
       *  List of Socket: [socket1, socket2]
       *  List of Objects: [{socket: socket1, weight:1}, {socket: Socket2, weight:0}]
       *  List of Objects and Socket: [{socket: socket1}, socket2]
       */
      List<SIPUASocketInterface> copy = <SIPUASocketInterface>[];
      if (sockets is List && sockets!.isNotEmpty) {
        for (SIPUASocketInterface socket in sockets) {
          copy.add(socket);
        }
      } else {
        throw Exceptions.ConfigurationError('sockets', sockets);
      }

      dst!.sockets = copy;
    },
    'uri': (Settings src, Settings? dst) {
      if (src.uri == null && dst!.uri == null) {
        throw Exceptions.ConfigurationError('uri', null);
      }
      URI uri = src.uri!;
      if (!uri.toString().contains(RegExp(r'^sip:', caseSensitive: false))) {
        uri.scheme = DartSIP_C.SIP;
      }
      dst!.uri = uri;
    },
    'transport_type': (Settings src, Settings? dst) {
      dynamic transportType = src.transportType;
      if (src.transportType == null && dst!.transportType == null) {
        throw Exceptions.ConfigurationError('transport type', null);
      }
      dst!.transportType = transportType;
    }
  };
  Map<String, Null Function(Settings src, Settings? dst)> optional =
      <String, Null Function(Settings src, Settings? dst)>{
    'authorization_user': (Settings src, Settings? dst) {
      String? authorization_user = src.authorization_user;
      if (authorization_user == null) return;
      if (Grammar.parse('"$authorization_user"', 'quoted_string') == -1) {
        return;
      } else {
        dst!.authorization_user = authorization_user;
      }
    },
    'user_agent': (Settings src, Settings? dst) {
      String user_agent = src.user_agent;
      if (user_agent == null) return;
      dst!.user_agent = user_agent;
    },
    'connection_recovery_max_interval': (Settings src, Settings? dst) {
      int connection_recovery_max_interval =
          src.connection_recovery_max_interval;
      if (connection_recovery_max_interval == null) return;
      if (connection_recovery_max_interval > 0) {
        dst!.connection_recovery_max_interval =
            connection_recovery_max_interval;
      }
    },
    'connection_recovery_min_interval': (Settings src, Settings? dst) {
      int connection_recovery_min_interval =
          src.connection_recovery_min_interval;
      if (connection_recovery_min_interval == null) return;
      if (connection_recovery_min_interval > 0) {
        dst!.connection_recovery_min_interval =
            connection_recovery_min_interval;
      }
    },
    'contact_uri': (Settings src, Settings? dst) {
      dynamic contact_uri = src.contact_uri;
      if (contact_uri == null) return;
      if (contact_uri is String) {
        dynamic uri = Grammar.parse(contact_uri, 'SIP_URI');
        if (uri != -1) {
          dst!.contact_uri = uri;
        }
      }
    },
    'display_name': (Settings src, Settings? dst) {
      String? display_name = src.display_name;
      if (display_name == null) return;
      dst!.display_name = display_name;
    },
    'instance_id': (Settings src, Settings? dst) {
      String? instance_id = src.instance_id;
      if (instance_id == null) return;
      if (instance_id.contains(RegExp(r'^uuid:', caseSensitive: false))) {
        instance_id = instance_id.substring(5);
      }
      if (Grammar.parse(instance_id, 'uuid') == -1) {
        return;
      } else {
        dst!.instance_id = instance_id;
      }
    },
    'no_answer_timeout': (Settings src, Settings? dst) {
      int no_answer_timeout = src.no_answer_timeout;
      if (no_answer_timeout == null) return;
      if (no_answer_timeout > 0) {
        dst!.no_answer_timeout = no_answer_timeout;
      }
    },
    'session_timers': (Settings src, Settings? dst) {
      bool session_timers = src.session_timers;
      if (session_timers == null) return;
      dst!.session_timers = session_timers;
    },
    'session_timers_refresh_method': (Settings src, Settings? dst) {
      SipMethod method = src.session_timers_refresh_method;
      if (method == SipMethod.INVITE || method == SipMethod.UPDATE) {
        dst!.session_timers_refresh_method = method;
      }
    },
    'password': (Settings src, Settings? dst) {
      String? password = src.password;
      if (password == null) return;
      dst!.password = password.toString();
    },
    'realm': (Settings src, Settings? dst) {
      String? realm = src.realm;
      if (realm == null) return;
      dst!.realm = realm.toString();
    },
    'ha1': (Settings src, Settings? dst) {
      String? ha1 = src.ha1;
      if (ha1 == null) return;
      dst!.ha1 = ha1.toString();
    },
    'register': (Settings src, Settings? dst) {
      bool? register = src.register;
      if (register == null) return;
      dst!.register = register;
    },
    'register_expires': (Settings src, Settings? dst) {
      int? register_expires = src.register_expires;
      if (register_expires == null) return;
      if (register_expires > 0) {
        dst!.register_expires = register_expires;
      }
    },
    'registrar_server': (Settings src, Settings? dst) {
      dynamic registrar_server = src.registrar_server;
      if (registrar_server == null) return;
      if (!registrar_server.contains(RegExp(r'^sip:', caseSensitive: false))) {
        registrar_server = '${DartSIP_C.SIP}:$registrar_server';
      }
      dynamic parsed = URI.parse(registrar_server);
      if (parsed == null || parsed.user != null) {
        return;
      } else {
        dst!.registrar_server = parsed;
      }
    },
    'register_extra_headers': (Settings src, Settings? dst) {
      List<String>? register_extra_headers = src.register_extra_headers;
      if (register_extra_headers == null) return;
      dst?.register_extra_headers = register_extra_headers;
    },
    'register_extra_contact_uri_params': (Settings src, Settings? dst) {
      Map<String, dynamic>? register_extra_contact_uri_params =
          src.register_extra_contact_uri_params;
      if (register_extra_contact_uri_params == null) return;
      dst!.register_extra_contact_uri_params =
          register_extra_contact_uri_params;
    },
    'use_preloaded_route': (Settings src, Settings? dst) {
      bool use_preloaded_route = src.use_preloaded_route;
      if (use_preloaded_route == null) return;
      dst!.use_preloaded_route = use_preloaded_route;
    },
    'dtmf_mode': (Settings src, Settings? dst) {
      DtmfMode dtmf_mode = src.dtmf_mode;
      if (dtmf_mode == null) return;
      dst!.dtmf_mode = dtmf_mode;
    },
    'ice_gathering_timeout': (Settings src, Settings? dst) {
      dst!.ice_gathering_timeout = src.ice_gathering_timeout;
    }
  };
}

final Checks checks = Checks();

void load(Settings src, Settings? dst) {
  try {
    // Check Mandatory parameters.
    checks.mandatory
        .forEach((String parameter, Null Function(Settings, Settings?) fun) {
      logger.i('Check mandatory parameter => $parameter.');
      fun(src, dst);
    });

    // Check Optional parameters.
    checks.optional
        .forEach((String parameter, Null Function(Settings, Settings?) fun) {
      logger.d('Check optional parameter => $parameter.');
      fun(src, dst);
    });
  } catch (e) {
    logger.e('Failed to load config: ${e.toString()}');
    rethrow;
  }
}
