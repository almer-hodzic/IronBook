import 'package:flutter/material.dart';

import 'screens/center_list_screen.dart';
import 'screens/trainer_dashboard_screen.dart';
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
  late final Map<String, WidgetBuilder> _roots;

  @override
  void initState() {
    super.initState();
    _api = widget.authApiService ?? createAuthApiService();
    _auth = AuthController(_api);
    final centers =
        widget.centerApiService ??
        CenterApiService(accessTokenProvider: _api.sessions);
    _roots = {
      AuthRoles.member: (_) => CenterListScreen(
        centerApiService: centers,
        logoutAction: AuthLogoutButton(controller: _auth),
      ),
      AuthRoles.trainer: (_) => TrainerDashboardScreen(
        centerApiService: centers,
        logoutAction: AuthLogoutButton(controller: _auth),
      ),
    };
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
        authenticatedRoots: _roots,
        appTitle: 'IronBook Mobile',
      ),
    );
  }
}
