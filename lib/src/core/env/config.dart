// ignore_for_file: constant_identifier_names
class EnvConfig {
  static const ENV_NAME = String.fromEnvironment(
    'ENV_NAME',
    defaultValue: 'staging',
  );
  static const String GRAPHQL_API_HOST = String.fromEnvironment('GRAPHQL_API_HOST', defaultValue: 'https://api.stage.cloudcall.blue/graphql');
  static const String GRAPHQL_API_KEY = String.fromEnvironment('GRAPHQL_API_KEY', defaultValue: 'da2-n3k33lym6jg2ln5qowpqboelke');
  static const String REAL_TIME_API_HOST = String.fromEnvironment('REAL_TIME_API_HOST', defaultValue: 'wss://api.stage.cloudcall.blue/graphql/realtime');
  static const String SEGMENT_API_KEY = String.fromEnvironment('SEGMENT_API_KEY', defaultValue: 'cpXDMeHyKj9PF0Kxq8wACROJBvRKxj01');
  static const String WEBSOCKET_ENDPOINT_HEALTH_CHECK_URL = String.fromEnvironment('WEBSOCKET_ENDPOINT_HEALTH_CHECK_URL', defaultValue: 'https://staging.webrtc-lookup.geovpn.mimas.starbug.ninja');
  static const bool USE_ANSI_COLOR_IN_LOGS = String.fromEnvironment('USE_ANSI_COLOR_IN_LOGS', defaultValue: 'false') == 'true';
  static const bool LOGGING_ENABLED = String.fromEnvironment('LOGGING_ENABLED', defaultValue: 'false') == 'true';
  static const bool PRINT_DEBUG_LOGS = String.fromEnvironment('PRINT_DEBUG_LOGS', defaultValue: 'false') == 'true';
}
