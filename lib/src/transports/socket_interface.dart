abstract class SIPUASocketInterface {
  String? get url;
  String? get sip_uri;
  String get via_transport;
  int? get weight;
  set via_transport(String value);

  void Function()? onconnect;
  void Function(SIPUASocketInterface socket, bool error, int? closeCode,
      String? reason)? ondisconnect;
  void Function(dynamic data)? ondata;

  void connect();
  void disconnect();
  bool send(dynamic message);
  bool isConnected();
  bool isConnecting();
}
