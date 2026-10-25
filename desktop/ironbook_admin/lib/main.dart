import 'package:flutter/material.dart';

import 'screens/admin_shell.dart';
import 'services/auth_services.dart';
import 'services/admin_center_api_service.dart';
import 'services/admin_check_in_api_service.dart';
import 'services/admin_coaching_request_api_service.dart';
import 'services/admin_group_training_api_service.dart';
import 'services/admin_membership_plan_api_service.dart';
import 'services/admin_trainer_api_service.dart';
import 'services/admin_reports_api_service.dart';
import 'services/admin_payment_api_service.dart';
import 'theme/ironbook_admin_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IronBookAdminApp());
}

class IronBookAdminApp extends StatefulWidget {
  const IronBookAdminApp({super.key, this.authApiService});

  final AuthApiService? authApiService;

  @override
  State<IronBookAdminApp> createState() => _IronBookAdminAppState();
}

class _IronBookAdminAppState extends State<IronBookAdminApp> {
  late final AuthApiService _api;
  late final AuthController _auth;
  late final Widget _home;

  @override
  void initState() {
    super.initState();
    _api = widget.authApiService ?? createAuthApiService();
    _auth = AuthController(_api);
    _home = AdminShell(
      centerApiService: AdminCenterApiService(),
      checkInApiService: AdminCheckInApiService(),
      coachingRequestApiService: AdminCoachingRequestApiService(),
      groupTrainingApiService: AdminGroupTrainingApiService(),
      membershipPlanApiService: AdminMembershipPlanApiService(),
      trainerApiService: AdminTrainerApiService(),
      reportsApiService: AdminReportsApiService(),
      paymentApiService: AdminPaymentApiService(),
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
      title: 'IronBook Admin',
      theme: IronBookAdminTheme.theme,
      home: AuthGate(
        controller: _auth,
        home: _home,
        appTitle: 'IronBook Admin',
      ),
    );
  }
}
