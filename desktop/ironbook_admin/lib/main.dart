import 'package:flutter/material.dart';

import 'screens/admin_shell.dart';
import 'services/admin_center_api_service.dart';

void main() {
  runApp(const IronBookAdminApp());
}

class IronBookAdminApp extends StatelessWidget {
  const IronBookAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IronBook Admin',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF314B7A),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      home: AdminShell(centerApiService: AdminCenterApiService()),
    );
  }
}
