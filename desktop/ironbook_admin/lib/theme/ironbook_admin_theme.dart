import 'package:flutter/material.dart';

import 'ironbook_admin_colors.dart';

class IronBookAdminTheme {
  const IronBookAdminTheme._();

  static ThemeData get theme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: IronBookAdminColors.slate900,
      brightness: Brightness.light,
    );

    return ThemeData(
      colorScheme: colorScheme,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: IronBookAdminColors.pageBottom,
      useMaterial3: true,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: IronBookAdminColors.slate900,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        headlineSmall: TextStyle(
          color: IronBookAdminColors.slate900,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        titleMedium: TextStyle(
          color: IronBookAdminColors.slate800,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(
          color: IronBookAdminColors.slate600,
          fontSize: 13,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          color: IronBookAdminColors.slate500,
          fontSize: 12,
          height: 1.35,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: IronBookAdminColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: IronBookAdminColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: IronBookAdminColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: IronBookAdminColors.borderStrong),
        ),
        labelStyle: const TextStyle(
          color: IronBookAdminColors.slate600,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(
          color: IronBookAdminColors.slate400,
          fontSize: 13,
        ),
      ),
    );
  }
}
