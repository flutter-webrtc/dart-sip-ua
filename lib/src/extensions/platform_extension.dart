import 'dart:io';

extension PlatformExtension on Platform {
  static bool get isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  static bool get isMobile => Platform.isIOS || Platform.isAndroid;
}
