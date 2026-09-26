import 'package:flutter/material.dart';

import 'screens/center_list_screen.dart';
import 'services/center_api_service.dart';

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
      home: CenterListScreen(centerApiService: CenterApiService()),
    );
  }
}
