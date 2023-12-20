import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sip_ua/src/sip_ua_helper.dart';
import '../logger.dart';

typedef OnMessageCallback = void Function(dynamic msg);
typedef OnCloseCallback = void Function(int? code, String? reason);
typedef OnOpenCallback = void Function();

class TcpSocketImpl {
  TcpSocketImpl(this.messageDelay, this._host, this._port);

  final String _host;
  final String _port;

  Socket? _socket;
  OnOpenCallback? onOpen;
  OnMessageCallback? onData;
  OnCloseCallback? onClose;
  final int messageDelay;

  void connect(
      {Iterable<String>? protocols,
      required TcpSocketSettings tcpSocketSettings}) async {
    handleQueue();
    logger.i('connect $_host:$_port');
    try {
      if (tcpSocketSettings.allowBadCertificate) {
        // /// Allow self-signed certificate, for test only.
        // _socket = await _connectForBadCertificate(_url, tcpSocketSettings);
      } else {
        // used to have these
        //protocols: protocols, headers: webSocketSettings.extraHeaders
        _socket = await Socket.connect(
          _host,
          int.parse(_port),
        );
      }

      onOpen?.call();

      _socket!.listen((dynamic data) {
        onData?.call(data);
      }, onDone: () {
        //  onClose?.call(_socket!., _socket!.closeReason);
      });
    } catch (e) {
      onClose?.call(500, e.toString());
    }
  }

  final StreamController<dynamic> queue = StreamController<dynamic>.broadcast();
  void handleQueue() async {
    queue.stream.asyncMap((dynamic event) async {
      await Future<void>.delayed(Duration(milliseconds: messageDelay));
      return event;
    }).listen((dynamic event) async {
      _socket!.add(event.codeUnits);
      logger.d('send: \n\n$event');
    });
  }

  void send(dynamic data) async {
    if (_socket != null) {
      queue.add(data);
    }
  }

  void close() {
    _socket!.close();
  }

  /// For test only.
  // Future<Socket> _connectForBadCertificate(
  //     String url, TcpSocketSettings tcpSocketSettings) async {
  //   try {
  //     Random r = Random();
  //     String key = base64.encode(List<int>.generate(16, (_) => r.nextInt(255)));
  //     SecurityContext securityContext = SecurityContext();
  //     HttpClient client = HttpClient(context: securityContext);

  //     if (tcpSocketSettings.userAgent != null) {
  //       client.userAgent = tcpSocketSettings.userAgent;
  //     }

  //     client.badCertificateCallback =
  //         (X509Certificate cert, String host, int port) {
  //       logger.w('Allow self-signed certificate => $host:$port. ');
  //       return true;
  //     };

  //     Uri parsed_uri = Uri.parse(url);
  //     Uri uri = parsed_uri.replace(
  //         scheme: parsed_uri.scheme == 'tcp' ? 'https' : 'http');

  //     HttpClientRequest request =
  //         await client.getUrl(uri); // form the correct url here
  //     request.headers.add('Connection', 'Upgrade', preserveHeaderCase: true);
  //     request.headers.add('Upgrade', 'websocket', preserveHeaderCase: true);
  //     request.headers.add('Sec-WebSocket-Version', '13',
  //         preserveHeaderCase: true); // insert the correct version here
  //     request.headers.add('Sec-WebSocket-Key', key.toLowerCase(),
  //         preserveHeaderCase: true);
  //     request.headers
  //         .add('Sec-WebSocket-Protocol', 'sip', preserveHeaderCase: true);

  //     tcpSocketSettings.extraHeaders.forEach((String key, dynamic value) {
  //       request.headers.add(key, value, preserveHeaderCase: true);
  //     });

  //     HttpClientResponse response = await request.close();
  //     Socket socket = await response.detachSocket();
  //     WebSocket webSocket = Socket. fromUpgradedSocket(
  //       socket,
  //       protocol: 'sip',
  //       serverSide: false,
  //     );

  //     return webSocket;
  //   } catch (e) {
  //     logger.e('error $e');
  //     throw e;
  //   }
  // }
}
