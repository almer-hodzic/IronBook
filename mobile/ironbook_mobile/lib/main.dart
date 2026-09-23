import 'package:flutter/material.dart';

import 'app_config.dart';

void main() {
  runApp(const IronBookMobileApp());
}

class IronBookMobileApp extends StatelessWidget {
  const IronBookMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IronBook Mobile',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF236A4B)),
        useMaterial3: true,
      ),
      home: const MobileFoundationScreen(),
    );
  }
}

class MobileFoundationScreen extends StatelessWidget {
  const MobileFoundationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('IronBook')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Member and Trainer mobile app', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 16),
                const Text('Phase 1 foundation is ready. Authentication, center selection, memberships, trainings, QR check-in, and progress logs are planned for later phases.'),
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
