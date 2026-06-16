import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nowa_runtime/nowa_runtime.dart';

@NowaGenerated()
class AppTheme {
  static const Color pureBlack = const Color(0xFF000000);

  static const Color surfaceGray = const Color(0xFF0B0B0C);

  static const Color appleBlue = const Color(0xFF0A84FF);

  static const Color appleRed = const Color(0xFFFF453A);

  static const Color incomingBubble = const Color(0xFF1C1C1E);

  static const Color secondaryText = const Color(0xFF8E8E93);

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: pureBlack,
    primaryColor: appleBlue,
    colorScheme: const ColorScheme.dark(
      primary: appleBlue,
      secondary: appleBlue,
      surface: surfaceGray,
      error: appleRed,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.37,
        color: Colors.white,
      ),
      bodyLarge: TextStyle(
        fontSize: 17,
        letterSpacing: -0.41,
        color: Colors.white,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        letterSpacing: -0.24,
        color: secondaryText,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
  );

  static const BorderRadius squircleRadius = const BorderRadius.all(
    Radius.circular(22),
  );

  static ShapeBorder squircleShape = const RoundedRectangleBorder(
    borderRadius: squircleRadius,
  );

  static ThemeData amoledTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: pureBlack,
    primaryColor: appleBlue,
    colorScheme: const ColorScheme.dark(
      primary: appleBlue,
      secondary: appleBlue,
      surface: pureBlack,
      error: appleRed,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.37,
        color: Colors.white,
      ),
      bodyLarge: TextStyle(
        fontSize: 17,
        letterSpacing: -0.41,
        color: Colors.white,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        letterSpacing: -0.24,
        color: secondaryText,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
  );

  static ThemeData plusTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF1A0B0B),
    primaryColor: const Color(0xFFFF4D4D),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFFF4D4D),
      secondary: Color(0xFFFF4D4D),
      surface: Color(0xFF2D1616),
      error: appleRed,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.37,
        color: Colors.white,
      ),
      bodyLarge: TextStyle(
        fontSize: 17,
        letterSpacing: -0.41,
        color: Colors.white,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        letterSpacing: -0.24,
        color: Color(0xFFE0C0C0),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
  );

  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: appleBlue,
    colorScheme: const ColorScheme.light(
      primary: appleBlue,
      secondary: appleBlue,
      surface: Colors.white,
      error: appleRed,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.37,
        color: Colors.black,
      ),
      bodyLarge: TextStyle(
        fontSize: 17,
        letterSpacing: -0.41,
        color: Colors.black,
      ),
      bodyMedium: TextStyle(
        fontSize: 15,
        letterSpacing: -0.24,
        color: Colors.black54,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
  );
}
