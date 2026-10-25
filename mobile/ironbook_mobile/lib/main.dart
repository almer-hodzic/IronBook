import 'package:flutter/material.dart';

import 'screens/center_list_screen.dart';
import 'services/center_api_service.dart';
import 'services/auth_services.dart';
import 'theme/ironbook_mobile_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IronBookMobileApp());
}

class IronBookMobileApp extends StatefulWidget {
  const IronBookMobileApp({
    super.key,
    this.authApiService,
    this.centerApiService,
  });

  final AuthApiService? authApiService;
  final CenterApiService? centerApiService;

  @override
  State<IronBookMobileApp> createState() => _IronBookMobileAppState();
}

class _IronBookMobileAppState extends State<IronBookMobileApp> {
  late final AuthApiService _api;
  late final AuthController _auth;
  late final Widget _home;

  @override
  void initState() {
    super.initState();
    _api = widget.authApiService ?? createAuthApiService();
    _auth = AuthController(_api);
    _home = CenterListScreen(
      centerApiService: widget.centerApiService ?? CenterApiService(),
      logoutAction: AuthLogoutButton(controller: _auth),
    );
  }

  @override
  void dispose() {
    _auth.dispose();
    if (widget.authApiService == null) _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IronBook Mobile',
      theme: IronBookMobileTheme.theme,
      home: AuthGate(
        controller: _auth,
        home: _home,
        appTitle: 'IronBook Mobile',
      ),
    );
  }
}
