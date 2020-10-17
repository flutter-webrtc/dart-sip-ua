import 'constants.dart';
import 'constants.dart' as DartSIP_C;
import 'exceptions.dart' as Exceptions;
import 'grammar.dart';
import 'logger.dart';
import 'socket.dart' as Socket;
import 'transports/websocket_interface.dart';
import 'uri.dart';
import 'utils.dart' as Utils;

// Default settings.
class Settings {
  // SIP authentication.
  String authorization_user;
  String password;
  String realm;
  String ha1;

  // SIP account.
  String display_name;
  dynamic uri;
  dynamic contact_uri;
  String user_agent = DartSIP_C.USER_AGENT;

  // SIP instance id (GRUU).
  String instance_id = null;

  // Preloaded SIP Route header field.
  bool use_preloaded_route = false;

  // Session parameters.
  bool session_timers = true;
  SipMethod session_timers_refresh_method = SipMethod.UPDATE;
  int no_answer_timeout = 60;

  // Registration parameters.
  bool register = true;
  int register_expires = 600;
  dynamic registrar_server;
  Map<String, dynamic> register_extra_contact_uri_params;

  // Connection options.
  List<WebSocketInterface> sockets = <WebSocketInterface>[];
  int connection_recovery_max_interval = 30;
  int connection_recovery_min_interval = 2;

  /*
   * Host address.
   * Value to be set in Via sent_by and host part of Contact FQDN.
  */
  String via_host = '${Utils.createRandomToken(12)}.invalid';

  // DartSIP ID
  String jssip_id;

  String hostport_params;
}

// Configuration checks.
class Checks {
  Map<String, Null Function(Settings src, Settings dst)> mandatory = {
    'sockets': (Settings src, Settings dst) {
      List<WebSocketInterface> sockets = src.sockets;
      /* Allow defining sockets parameter as:
       *  Socket: socket
       *  List of Socket: [socket1, socket2]
       *  List of Objects: [{socket: socket1, weight:1}, {socket: Socket2, weight:0}]
       *  List of Objects and Socket: [{socket: socket1}, socket2]
       */
      List<WebSocketInterface> _sockets = <WebSocketInterface>[];
      if (sockets is List && sockets.length > 0) {
        for (WebSocketInterface socket in sockets) {
          if (Socket.isSocket(socket)) {
            _sockets.add(socket);
          }
        }
      } else {
        throw Exceptions.ConfigurationError('sockets', sockets);
      }

      dst.sockets = _sockets;
    },
    'uri': (src, dst) {
      var uri = src.uri;
      if (src.uri == null && dst.uri == null) {
        throw Exceptions.ConfigurationError("uri", null);
      }
      if (!uri.contains(RegExp(r'^sip:', caseSensitive: false))) {
        uri = '${DartSIP_C.SIP}:${uri}';
      }
      var parsed = URI.parse(uri);
      if (parsed == null) {
        throw Exceptions.ConfigurationError('uri', parsed);
      } else if (parsed.user == null) {
        throw Exceptions.ConfigurationError('uri', parsed);
      } else {
        dst.uri = parsed;
      }
    }
  };
  var optional = {
    'authorization_user': (src, dst) {
      var authorization_user = src.authorization_user;
      if (authorization_user == null) return;
      if (Grammar.parse('"${authorization_user}"', 'quoted_string') == -1) {
        return;
      } else {
        dst.authorization_user = authorization_user;
      }
    },
    'user_agent': (src, dst) {
      var user_agent = src.user_agent;
      if (user_agent == null) return;
      if (user_agent is String) {
        dst.user_agent = user_agent;
      }
    },
    'connection_recovery_max_interval': (src, dst) {
      var connection_recovery_max_interval =
          src.connection_recovery_max_interval;
      if (connection_recovery_max_interval == null) return;
      if (connection_recovery_max_interval > 0) {
        dst.connection_recovery_max_interval = connection_recovery_max_interval;
      }
    },
    'connection_recovery_min_interval': (src, dst) {
      var connection_recovery_min_interval =
          src.connection_recovery_min_interval;
      if (connection_recovery_min_interval == null) return;
      if (connection_recovery_min_interval > 0) {
        dst.connection_recovery_min_interval = connection_recovery_min_interval;
      }
    },
    'contact_uri': (src, dst) {
      var contact_uri = src.contact_uri;
      if (contact_uri == null) return;
      if (contact_uri is String) {
        var uri = Grammar.parse(contact_uri, 'SIP_URI');
        if (uri != -1) {
          dst.contact_uri = uri;
        }
      }
    },
    'display_name': (src, dst) {
      var display_name = src.display_name;
      if (display_name == null) return;
      dst.display_name = display_name;
    },
    'instance_id': (src, dst) {
      var instance_id = src.instance_id;
      if (instance_id == null) return;
      if (instance_id.contains(RegExp(r'^uuid:', caseSensitive: false))) {
        instance_id = instance_id.substr(5);
      }
      if (Grammar.parse(instance_id, 'uuid') == -1) {
        return;
      } else {
        dst.instance_id = instance_id;
      }
    },
    'no_answer_timeout': (src, dst) {
      var no_answer_timeout = src.no_answer_timeout;
      if (no_answer_timeout == null) return;
      if (no_answer_timeout > 0) {
        dst.no_answer_timeout = no_answer_timeout;
      }
    },
    'session_timers': (src, dst) {
      var session_timers = src.session_timers;
      if (session_timers == null) return;
      if (session_timers is bool) {
        dst.session_timers = session_timers;
      }
    },
    'session_timers_refresh_method': (src, dst) {
      Settings srcSettings = src as Settings;
      Settings dstSettings = dst as Settings;
      SipMethod method = srcSettings.session_timers_refresh_method;
      if (method == SipMethod.INVITE || method == SipMethod.UPDATE) {
        dstSettings.session_timers_refresh_method = method;
      }
    },
    'password': (src, dst) {
      var password = src.password;
      if (password == null) return;
      dst.password = password.toString();
    },
    'realm': (src, dst) {
      var realm = src.realm;
      if (realm == null) return;
      dst.realm = realm.toString();
    },
    'ha1': (src, dst) {
      var ha1 = src.ha1;
      if (ha1 == null) return;
      dst.ha1 = ha1.toString();
    },
    'register': (src, dst) {
      var register = src.register;
      if (register == null) return;
      if (register is bool) {
        dst.register = register;
      }
    },
    'register_expires': (src, dst) {
      var register_expires = src.register_expires;
      if (register_expires == null) return;
      if (register_expires > 0) {
        dst.register_expires = register_expires;
      }
    },
    'registrar_server': (src, dst) {
      var registrar_server = src.registrar_server;
      if (registrar_server == null) return;
      if (!registrar_server.contains(RegExp(r'^sip:', caseSensitive: false))) {
        registrar_server = '${DartSIP_C.SIP}:${registrar_server}';
      }
      var parsed = URI.parse(registrar_server);
      if (parsed == null || parsed.user != null) {
        return;
      } else {
        dst.registrar_server = parsed;
      }
    },
    'register_extra_contact_uri_params': (src, dst) {
      var register_extra_contact_uri_params =
          src.register_extra_contact_uri_params;
      if (register_extra_contact_uri_params == null) return;
      if (register_extra_contact_uri_params is Map<String, dynamic>) {
        dst.register_extra_contact_uri_params =
            register_extra_contact_uri_params;
      }
    },
    'use_preloaded_route': (src, dst) {
      var use_preloaded_route = src.use_preloaded_route;
      if (use_preloaded_route == null) return;
      if (use_preloaded_route is bool) {
        dst.use_preloaded_route = use_preloaded_route;
      }
    }
  };
}

final Checks checks = Checks();

void load(dst, src) {
  try {
    // Check Mandatory parameters.
    checks.mandatory.forEach((String parameter, fun) {
      logger.info('Check mandatory parameter => ${parameter}.');
      fun(src, dst);
    });

    // Check Optional parameters.
    checks.optional.forEach((String parameter, fun) {
      logger.debug('Check optional parameter => ${parameter}.');
      fun(src, dst);
    });
  } catch (e) {
    logger.error('Failed to load config: ${e.toString()}');
    throw e;
  }
}
