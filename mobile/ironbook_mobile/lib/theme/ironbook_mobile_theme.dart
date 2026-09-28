import 'package:flutter/material.dart';

import 'ironbook_mobile_colors.dart';

class IronBookMobileTheme {
  const IronBookMobileTheme._();

  static ThemeData get theme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: IronBookMobileColors.accent,
      brightness: Brightness.light,
    );

    return ThemeData(
      colorScheme: colorScheme,
      fontFamily: 'Segoe UI',
      scaffoldBackgroundColor: IronBookMobileColors.backgroundTop,
      useMaterial3: true,
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: IronBookMobileColors.slate900,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          height: 1.16,
        ),
        titleMedium: TextStyle(
          color: IronBookMobileColors.slate800,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: TextStyle(
          color: IronBookMobileColors.slate600,
          fontSize: 13,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          color: IronBookMobileColors.slate500,
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}
