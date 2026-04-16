import 'package:flutter/material.dart';

class AppTheme {
  // Primary Colors
  static const Color primaryColor = Color(0xFFAE26F7);
  static const Color backgroundColor = Color(0xFFF7EBFE);
  
  // Secondary / Accent Colors
  static const Color accentColor = Color(0xFFD38BFF);
  static const Color surfaceColor = Colors.white;
  static const Color textColor = Color(0xFF2D004D);
  static const Color subtitleColor = Color(0xFF6B4D81);
  static const Color unselectedColor = Color(0xFF4C0674);

  // Gradient for Glowing Effect
  static const LinearGradient glowingGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFAE26F7),
      Color(0xFFD38BFF),
      Color(0xFFAE26F7),
    ],
  );

  // Background Glowing Gradient
  static const RadialGradient bgGlowingEffect = RadialGradient(
    center: Alignment(0, -0.5),
    radius: 1.5,
    colors: [
      Color(0xFFF7EBFE),
      Color(0xFFF7EBFE),
    ],
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      primaryColor: primaryColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: accentColor,
        surface: surfaceColor,
        background: backgroundColor,
      ),
      scaffoldBackgroundColor: backgroundColor,
      
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textColor,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: textColor),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: primaryColor.withAlpha(50),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 8,
        shadowColor: primaryColor.withAlpha(20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: primaryColor,
        unselectedItemColor: unselectedColor,
        backgroundColor: surfaceColor,
        elevation: 10,
      ),

      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(color: textColor),
        bodyMedium: TextStyle(color: textColor),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withAlpha(200),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primaryColor.withAlpha(30)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        labelStyle: const TextStyle(color: subtitleColor),
      ),
    );
  }

  // Helper for Glowing Shadow
  static List<BoxShadow> get glowingShadow => [
    BoxShadow(
      color: primaryColor.withAlpha(40),
      blurRadius: 15,
      spreadRadius: 2,
      offset: const Offset(0, 4),
    ),
  ];
}
