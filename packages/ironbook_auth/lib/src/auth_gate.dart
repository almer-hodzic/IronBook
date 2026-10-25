import 'package:flutter/material.dart';

import 'auth_controller.dart';
import 'login_screen.dart';

/// Deliberately checks only authentication, never role.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.home,
    required this.appTitle,
  });

  final AuthController controller;
  final Widget home;
  final String appTitle;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    widget.controller.restore();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final auth = widget.controller;
      if (auth.isRestoring) {
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(
              semanticsLabel: 'Restoring session',
            ),
          ),
        );
      }
      if (auth.restoreFailed) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(auth.errorMessage!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: auth.restore,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      }
      if (auth.isAuthenticated) return widget.home;
      return LoginScreen(controller: auth, appTitle: widget.appTitle);
    },
  );
}

/// Inserted into each existing root's action area without changing navigation.
class AuthLogoutButton extends StatelessWidget {
  const AuthLogoutButton({super.key, required this.controller});
  final AuthController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => IconButton(
      tooltip: 'Log out',
      onPressed: controller.isBusy
          ? null
          : () async {
              await controller.logout();
              if (!context.mounted || controller.errorMessage == null) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(controller.errorMessage!)));
            },
      icon: controller.isBusy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.logout),
    ),
  );
}
