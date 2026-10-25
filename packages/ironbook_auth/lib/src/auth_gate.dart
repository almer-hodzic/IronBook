import 'package:flutter/material.dart';

import 'auth_controller.dart';
import 'auth_roles.dart';
import 'login_screen.dart';

/// Selects only explicitly supported platform roles after session restoration.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.authenticatedRoots,
    required this.appTitle,
  });

  final AuthController controller;
  final Map<String, WidgetBuilder> authenticatedRoots;
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
      if (auth.isAuthenticated) {
        final role = auth.session!.role;
        final root = AuthRoles.values.contains(role)
            ? widget.authenticatedRoots[role]
            : null;
        if (root != null) {
          return KeyedSubtree(key: ValueKey(role), child: root(context));
        }
        return _UnsupportedRoleScreen(
          controller: auth,
          appTitle: widget.appTitle,
        );
      }
      return LoginScreen(controller: auth, appTitle: widget.appTitle);
    },
  );
}

/// Inserted into each existing root's action area without changing navigation.
class AuthLogoutButton extends StatelessWidget {
  const AuthLogoutButton({super.key, required this.controller, this.label});
  final AuthController controller;
  final String? label;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final onPressed = controller.isBusy
          ? null
          : () async {
              await controller.logout();
              if (!context.mounted || controller.errorMessage == null) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(controller.errorMessage!)));
            };
      final icon = controller.isBusy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.logout);
      if (label != null) {
        return FilledButton.icon(
          onPressed: onPressed,
          icon: icon,
          label: Text(label!),
        );
      }
      return IconButton(tooltip: 'Log out', onPressed: onPressed, icon: icon);
    },
  );
}

class _UnsupportedRoleScreen extends StatelessWidget {
  const _UnsupportedRoleScreen({
    required this.controller,
    required this.appTitle,
  });

  final AuthController controller;
  final String appTitle;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appTitle,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'This account cannot use this app.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    AuthLogoutButton(controller: controller, label: 'Sign out'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
