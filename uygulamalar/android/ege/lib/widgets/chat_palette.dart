import 'package:flutter/material.dart';

/// Warm, quiet surfaces for the conversation workspace.
abstract final class ChatPalette {
  static bool dark = false;
  static Color chosenAccent = const Color(0xFFB85C3D);
  static bool configure(String mode, int accent, bool systemDark) {
    final nextDark = mode == 'dark' || (mode == 'system' && systemDark);
    final nextAccent = Color(accent | 0xFF000000);
    final changed = dark != nextDark || chosenAccent != nextAccent;
    dark = nextDark; chosenAccent = nextAccent;
    return changed;
  }
  static Color get background => dark ? const Color(0xFF141619) : const Color(0xFFFAF9F6);
  static Color get surface => dark ? const Color(0xFF202328) : Colors.white;
  static Color get soft => dark ? const Color(0xFF2A2D33) : const Color(0xFFF0EEE8);
  static Color get ink => dark ? const Color(0xFFF1F2F4) : const Color(0xFF30302E);
  static Color get muted => dark ? const Color(0xFFB1B5BD) : const Color(0xFF74736D);
  static Color get border => dark ? const Color(0xFF41464F) : const Color(0xFFE3E0D8);
  static Color get accent => chosenAccent;

  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: dark ? Brightness.dark : Brightness.light,
    ).copyWith(primary: accent, surface: surface, onSurface: ink),
    dividerColor: border,
    iconTheme: IconThemeData(color: ink),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      border: InputBorder.none,
      hintStyle: TextStyle(color: muted),
    ),
    textTheme: (dark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
      fontFamily: 'Roboto',
      bodyColor: ink,
      displayColor: ink,
    ),
  );
}
