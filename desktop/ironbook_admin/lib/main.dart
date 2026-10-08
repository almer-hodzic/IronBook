import 'package:flutter/material.dart';

import 'screens/admin_shell.dart';
import 'services/admin_center_api_service.dart';
import 'services/admin_check_in_api_service.dart';
import 'services/admin_group_training_api_service.dart';
import 'services/admin_membership_plan_api_service.dart';
import 'theme/ironbook_admin_theme.dart';

void main() {
  runApp(const IronBookAdminApp());
}

class IronBookAdminApp extends StatelessWidget {
  const IronBookAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IronBook Admin',
      theme: IronBookAdminTheme.theme,
      home: AdminShell(
        centerApiService: AdminCenterApiService(),
        checkInApiService: AdminCheckInApiService(),
        groupTrainingApiService: AdminGroupTrainingApiService(),
        membershipPlanApiService: AdminMembershipPlanApiService(),
      ),
    );
  }
}
