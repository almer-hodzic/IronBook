import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/app_config.dart';
import 'package:ironbook_mobile/services/auth_services.dart';

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
  test('auth factory follows existing API_BASE_URL configuration', () async {
    const configured = String.fromEnvironment('API_BASE_URL');
    expect(AppConfig.apiBaseUrl, configured);
    var called = false;
    final service = createAuthApiService(
      sessions: SessionStore(storage: MemoryStorage()),
      client: MockClient((request) async {
        called = true;
        final base = configured.replaceFirst(RegExp(r'/+$'), '');
        expect(request.url.toString(), '$base/api/auth/login');
        return http.Response(
          jsonEncode({
            'accessToken': 'fixture-token',
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
            'accountId': 1,
            'username': 'fixture',
            'role': 'Member',
          }),
          200,
        );
      }),
    );
    if (configured.isEmpty) {
      await expectLater(
        service.login(username: 'fixture', password: 'not-persisted'),
        throwsStateError,
      );
      expect(called, isFalse);
    } else {
      await service.login(username: 'fixture', password: 'not-persisted');
      expect(called, isTrue);
      expect(await service.sessions.getAccessToken(), 'fixture-token');
    }
  });
}
