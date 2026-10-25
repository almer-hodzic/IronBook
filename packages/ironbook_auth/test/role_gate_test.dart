import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_auth/ironbook_auth.dart';

class MemoryStorage implements SessionStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

void main() {
  test('shared roles match exact backend values', () {
    expect(AuthRoles.values, {'Member', 'Trainer', 'Admin'});
  });

  for (final role in [AuthRoles.member, AuthRoles.trainer, 'Unknown']) {
    testWidgets('gate builds only a supported known role: $role', (
      tester,
    ) async {
      final storage = MemoryStorage();
      final session = AuthSession(
        accessToken: 'fixture-token',
        expiresAt: DateTime.utc(2030, 1, 2),
        accountId: 1,
        username: 'fixture',
        role: role,
      );
      storage.value = jsonEncode(session.toJson());
      var requests = 0;
      final api = AuthApiService(
        apiBaseUrl: 'http://localhost:5100',
        sessions: SessionStore(storage: storage, now: () => DateTime.utc(2030)),
        client: MockClient((_) async {
          requests++;
          return http.Response('', 204);
        }),
      );
      final controller = AuthController(api);
      var built = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            controller: controller,
            appTitle: 'IronBook',
            authenticatedRoots: {
              AuthRoles.member: (_) {
                built++;
                return const Scaffold(body: Text('Member root'));
              },
              // Even a mistakenly supplied unknown mapping must not allow entry.
              'Unknown': (_) {
                built++;
                return const Text('Must not build');
              },
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (role == AuthRoles.member) {
        expect(built, 1);
        expect(find.text('Member root'), findsOneWidget);
      } else {
        expect(built, 0);
        expect(find.text('This account cannot use this app.'), findsOneWidget);
        expect(find.text('Must not build'), findsNothing);
      }
      expect(requests, 0);
      expect(storage.value, isNotNull);
      expect(controller.session!.role, role);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  for (final role in [null, '', '   ', 5]) {
    test('malformed role remains an invalid stored session: $role', () async {
      final storage = MemoryStorage()
        ..value = jsonEncode({
          'accessToken': 'fixture-token',
          'expiresAt': '2030-01-02T00:00:00Z',
          'accountId': 1,
          'username': 'fixture',
          'role': role,
        });
      final store = SessionStore(
        storage: storage,
        now: () => DateTime.utc(2030),
      );
      expect(await store.load(), isNull);
      expect(storage.value, isNull);
    });
  }
}
