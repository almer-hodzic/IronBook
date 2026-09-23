import 'package:flutter/material.dart';

import 'app_config.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF314B7A)),
        useMaterial3: true,
      ),
      home: const AdminFoundationScreen(),
    );
  }
}

class AdminFoundationScreen extends StatelessWidget {
  const AdminFoundationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('IronBook Admin')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Admin desktop app', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 16),
                const Text('Phase 1 foundation is ready. Dashboards, CRUD screens, payments, reports, and user assignments are planned for later phases.'),
                const SizedBox(height: 16),
                Text(
                  AppConfig.hasApiBaseUrl
                      ? 'API: ${AppConfig.apiBaseUrl}'
                      : 'API: configure with --dart-define=API_BASE_URL=...',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
