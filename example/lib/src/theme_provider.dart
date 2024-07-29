import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeData? currentTheme;

  ThemeProvider() {
    final brightness = PlatformDispatcher.instance.platformBrightness;

    currentTheme =
        brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
  }

  setLightMode() {
    currentTheme = ThemeData(
      primarySwatch: Colors.blue,
      fontFamily: 'Roboto',
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: Colors.grey),
        contentPadding: EdgeInsets.all(10.0),
        border:
            UnderlineInputBorder(borderSide: BorderSide(color: Colors.black12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.all(16),
          textStyle: TextStyle(fontSize: 18),
        ),
      ),
    );
    notifyListeners();
  }

  setDarkmode() {
    currentTheme = ThemeData.dark().copyWith(
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.all(16),
          textStyle: TextStyle(fontSize: 18),
        ),
      ),
    );
    notifyListeners();
  }
}
