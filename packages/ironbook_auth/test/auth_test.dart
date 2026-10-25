import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2030, 1, 1);
  Map<String, dynamic> sessionJson() => {
    'accessToken': 'test-access-token',
    'expiresAt': now.add(const Duration(hours: 1)).toIso8601String(),
    'accountId': 7,
    'username': 'sample-member',
    'role': 'Member',
  };
  late MemoryStorage storage;
  late SessionStore store;
  setUp(() {
    storage = MemoryStorage();
    store = SessionStore(storage: storage, now: () => now);
  });

  AuthApiService api(Future<http.Response> Function(http.Request) handler) =>
      AuthApiService(
        apiBaseUrl: 'http://localhost:5100/',
        sessions: store,
        client: MockClient(handler),
      );

  Future<void> seed() => store.save(AuthSession.fromJson(sessionJson()));

  test('parses the exact login fields and UTC expiry', () {
    final session = AuthSession.fromJson(sessionJson());
    expect(session.accountId, 7);
    expect(session.username, 'sample-member');
    expect(session.role, 'Member');
    expect(session.expiresAt.isUtc, isTrue);
    expect(session.toJson(), sessionJson());
  });

  test('malformed login response is rejected without persistence', () async {
    final service = api((_) async => http.Response('{"accessToken":"x"}', 200));
    await expectLater(
      service.login(username: 'x', password: 'private'),
      throwsFormatException,
    );
    expect(storage.value, isNull);
  });

  test(
    'login stores session but never password or unknown response fields',
    () async {
      final service = api((request) async {
        expect(request.url.toString(), 'http://localhost:5100/api/auth/login');
        expect(request.headers['Authorization'], isNull);
        expect(jsonDecode(request.body), {
          'username': 'sample-member',
          'password': 'private',
        });
        return http.Response(
          jsonEncode({...sessionJson(), 'password': 'never-store'}),
          200,
        );
      });
      await service.login(username: 'sample-member', password: 'private');
      expect(jsonDecode(storage.value!), sessionJson());
      expect(storage.value, isNot(contains('private')));
      expect(storage.value, isNot(contains('never-store')));
      expect(await store.isAuthenticated, isTrue);
    },
  );

  test(
    'failed login exposes HTTP status without storing a partial session',
    () async {
      final service = api((_) async => http.Response('{}', 401));
      await expectLater(
        service.login(username: 'x', password: 'wrong'),
        throwsA(
          isA<AuthApiException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
      expect(storage.value, isNull);
    },
  );

  test('failed login preserves an existing session', () async {
    await seed();
    final before = storage.value;
    await expectLater(
      api((_) async => http.Response('', 401))
          .login(username: 'other', password: 'wrong'),
      throwsA(isA<AuthApiException>()),
    );
    expect(storage.value, before);
  });

  test(
    'access token and role can be obtained from persisted storage',
    () async {
      await seed();
      final restored = SessionStore(storage: storage, now: () => now);
      expect(await restored.getAccessToken(), 'test-access-token');
      expect(await restored.getRole(), 'Member');
      expect((await restored.load())!.accountId, 7);
    },
  );

  test('absent session is unauthenticated', () async {
    expect(await store.load(), isNull);
    expect(await store.getAccessToken(), isNull);
    expect(await store.getRole(), isNull);
    expect(await store.isAuthenticated, isFalse);
  });

  for (final offset in [Duration.zero, const Duration(seconds: -1)]) {
    test(
      'expiry at or before now clears persisted credentials ($offset)',
      () async {
        storage.value = jsonEncode({
          ...sessionJson(),
          'expiresAt': now.add(offset).toIso8601String(),
        });
        expect(await store.load(), isNull);
        expect(storage.value, isNull);
      },
    );
  }

  test('malformed persisted session is cleared', () async {
    storage.value = 'not-json';
    expect(await store.load(), isNull);
    expect(storage.value, isNull);
  });

  test('expired login response is never persisted', () async {
    final service = api(
      (_) async => http.Response(
        jsonEncode({...sessionJson(), 'expiresAt': now.toIso8601String()}),
        200,
      ),
    );
    await expectLater(
      service.login(username: 'x', password: 'private'),
      throwsFormatException,
    );
    expect(storage.value, isNull);
  });

  for (final status in [204, 401]) {
    test('logout sends Bearer token and clears session on $status', () async {
      await seed();
      final service = api((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/auth/logout');
        expect(request.headers['Authorization'], 'Bearer test-access-token');
        expect(request.body, isEmpty);
        return http.Response('', status);
      });
      await service.logout();
      expect(storage.value, isNull);
      expect(await store.getRole(), isNull);
    });
  }

  test('logout without token makes no request', () async {
    await api((_) async => throw StateError('Unexpected request')).logout();
    expect(storage.value, isNull);
  });

  test('logout server failure preserves session and surfaces error', () async {
    await seed();
    await expectLater(
      api((_) async => http.Response('', 500)).logout(),
      throwsA(isA<AuthApiException>()),
    );
    expect(await store.getAccessToken(), isNotNull);
  });

  test(
    'change password sends exact body and Bearer, clears only after success',
    () async {
      await seed();
      final service = api((request) async {
        expect(request.url.path, '/api/auth/change-password');
        expect(request.headers['Authorization'], 'Bearer test-access-token');
        expect(jsonDecode(request.body), {
          'currentPassword': 'old-private',
          'newPassword': 'new-private',
        });
        expect(await store.isAuthenticated, isTrue);
        return http.Response('', 204);
      });
      await service.changePassword(
        currentPassword: 'old-private',
        newPassword: 'new-private',
      );
      expect(storage.value, isNull);
    },
  );

  test(
    'change password 400 preserves session, returns validation errors',
    () async {
      await seed();
      final before = storage.value;
      final service = api(
        (_) async => http.Response(
          jsonEncode({
            'errors': {
              'CurrentPassword': ['The current password is incorrect.'],
            },
          }),
          400,
        ),
      );
      await expectLater(
        service.changePassword(currentPassword: 'bad', newPassword: 'new'),
        throwsA(
          isA<AuthApiException>().having(
            (e) => e.errors.keys,
            'fields',
            contains('CurrentPassword'),
          ),
        ),
      );
      expect(storage.value, before);
    },
  );

  test(
    'change password 401 clears stale credentials and surfaces status',
    () async {
      await seed();
      await expectLater(
        api((_) async => http.Response('', 401))
            .changePassword(currentPassword: 'old', newPassword: 'new'),
        throwsA(
          isA<AuthApiException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
      expect(storage.value, isNull);
    },
  );

  test('change password without session makes no request', () async {
    await expectLater(
      api((_) async => throw StateError('Unexpected request'))
          .changePassword(currentPassword: 'old', newPassword: 'new'),
      throwsA(isA<AuthApiException>()),
    );
  });

  test(
    'transport failure is surfaced without modifying stored credentials',
    () async {
      await seed();
      final before = storage.value;
      await expectLater(
        api((_) async => throw http.ClientException('Offline')).logout(),
        throwsA(isA<http.ClientException>()),
      );
      expect(storage.value, before);
    },
  );

  test('clear removes entire token/session', () async {
    await seed();
    await store.clear();
    expect(storage.value, isNull);
    expect(await store.getAccessToken(), isNull);
    expect(await store.isAuthenticated, isFalse);
  });

  test(
    'secure-storage adapter persists, restores and clears its own key',
    () async {
      FlutterSecureStorage.setMockInitialValues({'unrelated': 'keep'});
      final secureStore = SessionStore(now: () => now);
      await secureStore.save(AuthSession.fromJson(sessionJson()));
      final restored = SessionStore(now: () => now);
      expect(await restored.getAccessToken(), 'test-access-token');
      await restored.clear();
      expect(await secureStore.load(), isNull);
      expect(await const FlutterSecureStorage().read(key: 'unrelated'), 'keep');
    },
  );
}
