import 'package:flutter/material.dart';

import 'screens/center_list_screen.dart';
import 'services/center_api_service.dart';
import 'theme/ironbook_mobile_theme.dart';

void main() {
  runApp(const IronBookMobileApp());
}

class IronBookMobileApp extends StatelessWidget {
  const IronBookMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IronBook Mobile',
      theme: IronBookMobileTheme.theme,
      home: CenterListScreen(centerApiService: CenterApiService()),
    );
  }
}
