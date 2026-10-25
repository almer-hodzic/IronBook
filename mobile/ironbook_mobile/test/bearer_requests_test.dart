import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_auth/ironbook_auth.dart';
import 'package:ironbook_mobile/models/member_profile.dart';
import 'package:ironbook_mobile/models/training_preferences.dart';
import 'package:ironbook_mobile/services/bearer_http_client.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';

import 'support/token_provider.dart';

class MemoryStorage implements SessionStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

class FailingTokenProvider implements AccessTokenProvider {
  @override
  Future<String?> getAccessToken() async =>
      throw StateError('private-fixture-token');
}

const profileJson = {
  'id': 7,
  'firstName': 'Mira',
  'lastName': 'Test',
  'email': 'mira@example.com',
  'phoneNumber': null,
  'isActive': true,
  'createdAt': '2026-01-15T10:00:00Z',
};
const preferenceJson = {
  'primaryGoal': 'Build Strength',
  'interests': ['strength', 'fat_loss'],
};
const preferences = TrainingPreferences(
  primaryGoal: 'Build Strength',
  interests: ['strength', 'fat_loss'],
);

void main() {
  final operations = <String, Future<Object?> Function(CenterApiService)>{
    'Profile GET': (api) => api.getMemberProfile(),
    'Profile PUT': (api) => api.updateMemberProfile(
      firstName: ' Mira ',
      lastName: ' Test ',
      email: ' mira@example.com ',
      phoneNumber: ' ',
    ),
    'Preferences GET': (api) => api.getTrainingPreferences(),
    'Preferences PUT': (api) => api.saveTrainingPreferences(preferences),
  };

  test('Bearer wrapper preserves headers/body and reads the current token for each request', () async {
    final tokens = FakeAccessTokenProvider('first-token');
    final requests = <http.Request>[];
    final client = BearerHttpClient(
      accessTokenProvider: tokens,
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      }),
    );
    await client.put(
      Uri.parse('http://localhost/resource'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer obsolete',
      },
      body: '{"value":1}',
    );
    tokens.token = 'second-token';
    await client.get(Uri.parse('http://localhost/resource'));
    expect(requests[0].headers['Authorization'], 'Bearer first-token');
    expect(requests[0].headers['Accept'], 'application/json');
    expect(requests[0].headers['Content-Type'], 'application/json');
    expect(requests[0].body, '{"value":1}');
    expect(
      requests[0].headers.keys.where(
        (key) => key.toLowerCase() == 'authorization',
      ),
      hasLength(1),
    );
    expect(requests[1].headers['Authorization'], 'Bearer second-token');
    expect(tokens.reads, 2);
    client.close();
  });

  for (final token in [
    null,
    '',
    ' ',
    'Bearer token',
    'token\r\nInjected: value',
    'token\n',
  ]) {
    test('missing/malformed token fails before sending ($token)', () async {
      var sent = false;
      final client = BearerHttpClient(
        accessTokenProvider: FakeAccessTokenProvider(token),
        client: MockClient((_) async {
          sent = true;
          return http.Response('', 200);
        }),
      );
      await expectLater(
        client.get(Uri.parse('http://localhost/resource')),
        throwsA(
          isA<AuthenticationRequiredException>().having(
            (error) => error.toString(),
            'safe message',
            'Authentication is required.',
          ),
        ),
      );
      expect(sent, isFalse);
      client.close();
    });
  }

  test('persisted session supplies token; expired session clears and sends nothing', () async {
    final now = DateTime.utc(2030, 1, 1);
    final storage = MemoryStorage();
    final store = SessionStore(storage: storage, now: () => now);
    var requests = 0;
    final client = BearerHttpClient(
      accessTokenProvider: store,
      client: MockClient((request) async {
        requests++;
        expect(request.headers['Authorization'], 'Bearer persisted-token');
        return http.Response('', 200);
      }),
    );
    final session = AuthSession(
      accessToken: 'persisted-token',
      expiresAt: now.add(const Duration(hours: 1)),
      accountId: 7,
      username: 'fixture',
      role: AuthRoles.member,
    );
    await store.save(session);
    await client.get(Uri.parse('http://localhost/resource'));
    storage.value = jsonEncode({
      ...session.toJson(),
      'expiresAt': now.toIso8601String(),
    });
    await expectLater(
      client.get(Uri.parse('http://localhost/resource')),
      throwsA(isA<AuthenticationRequiredException>()),
    );
    expect(requests, 1);
    expect(storage.value, isNull);
    client.close();
  });

  test(
    'token-provider errors expose no credential details and send nothing',
    () async {
      final client = BearerHttpClient(
        accessTokenProvider: FailingTokenProvider(),
        client: MockClient((_) async => throw StateError('Must not send')),
      );
      await expectLater(
        client.get(Uri.parse('http://localhost/resource')),
        throwsA(
          isA<AuthenticationRequiredException>().having(
            (error) => error.toString(),
            'safe message',
            'Authentication is required.',
          ),
        ),
      );
      client.close();
    },
  );

  for (final entry in operations.entries) {
    test('${entry.key} adds Bearer and preserves payload/parsing', () async {
      final tokens = FakeAccessTokenProvider();
      final api = CenterApiService(
        apiBaseUrl: 'http://10.0.2.2:5100',
        accessTokenProvider: tokens,
        client: MockClient((request) async {
          final isProfile = entry.key.startsWith('Profile');
          expect(
            request.headers['Authorization'],
            'Bearer fixture-access-token',
          );
          expect(request.url.host, '10.0.2.2');
          expect(
            request.url.path,
            isProfile
                ? '/api/member/profile'
                : '/api/member/training-preferences',
          );
          expect(request.method, entry.key.endsWith('PUT') ? 'PUT' : 'GET');
          if (request.method == 'PUT') {
            expect(request.headers['Content-Type'], 'application/json');
            expect(
              jsonDecode(request.body),
              isProfile
                  ? {
                      'firstName': 'Mira',
                      'lastName': 'Test',
                      'email': 'mira@example.com',
                      'phoneNumber': null,
                    }
                  : preferenceJson,
            );
          }
          return http.Response(
            jsonEncode(isProfile ? profileJson : preferenceJson),
            200,
          );
        }),
      );
      final result = await entry.value(api);
      if (result is TrainingPreferences) {
        expect(result.toJson(), preferenceJson);
      } else {
        final profile = result as MemberProfile;
        expect(profile.id, 7);
        expect(profile.firstName, 'Mira');
        expect(profile.email, 'mira@example.com');
        expect(profile.phoneNumber, isNull);
        expect(profile.isActive, isTrue);
        expect(profile.createdAt, DateTime.utc(2026, 1, 15, 10));
      }
    });

    test(
      '${entry.key} missing token is safe 401 without network/login',
      () async {
        final api = CenterApiService(
          apiBaseUrl: 'http://localhost',
          accessTokenProvider: FakeAccessTokenProvider(null),
          client: MockClient((_) async => throw StateError('Must not send')),
        );
        await expectLater(
          entry.value(api),
          throwsA(
            isA<CenterApiException>()
                .having((error) => error.statusCode, 'status', 401)
                .having(
                  (error) => error.toString(),
                  'message',
                  'Please log in to continue.',
                ),
          ),
        );
      },
    );

    test(
      '${entry.key} backend 401 stays observable without clearing credentials or leaking response',
      () async {
        final now = DateTime.utc(2030, 1, 1);
        final storage = MemoryStorage();
        final store = SessionStore(storage: storage, now: () => now);
        await store.save(
          AuthSession(
            accessToken: 'private-fixture-token',
            expiresAt: now.add(const Duration(hours: 1)),
            accountId: 7,
            username: 'fixture',
            role: AuthRoles.member,
          ),
        );
        final before = storage.value;
        var requests = 0;
        final api = CenterApiService(
          apiBaseUrl: 'http://localhost',
          accessTokenProvider: store,
          client: MockClient((request) async {
            requests++;
            return http.Response('{"detail":"private-fixture-token"}', 401);
          }),
        );
        await expectLater(
          entry.value(api),
          throwsA(
            isA<CenterApiException>()
                .having((error) => error.statusCode, 'status', 401)
                .having(
                  (error) => error.toString(),
                  'safe message',
                  isNot(contains('private-fixture-token')),
                ),
          ),
        );
        expect(storage.value, before);
        expect(requests, 1);
      },
    );
  }

  test('non-auth Profile and Preferences errors retain backend validation messages', () async {
    final api = CenterApiService(
      apiBaseUrl: 'http://localhost',
      accessTokenProvider: FakeAccessTokenProvider(),
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'errors': {
              'Field': ['Existing validation message.'],
            },
          }),
          400,
        ),
      ),
    );
    for (final operation in [
      operations['Profile GET']!,
      operations['Profile PUT']!,
      operations['Preferences PUT']!,
    ]) {
      await expectLater(
        operation(api),
        throwsA(
          isA<CenterApiException>().having(
            (error) => error.message,
            'message',
            'Existing validation message.',
          ),
        ),
      );
    }
    await expectLater(
      api.getTrainingPreferences(),
      throwsA(
        isA<CenterApiException>().having(
          (error) => error.message,
          'message',
          'Training preferences could not be loaded.',
        ),
      ),
    );
  });

  test('public Centers and Trainer catalog calls neither read token nor add Bearer', () async {
    final tokens = FakeAccessTokenProvider();
    final requests = <String>[];
    final api = CenterApiService(
      apiBaseUrl: 'http://localhost',
      accessTokenProvider: tokens,
      client: MockClient((request) async {
        requests.add(request.url.path);
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response('[]', 200);
      }),
    );
    await api.getCenters();
    await api.getTrainersForCenter(3);
    expect(tokens.reads, 0);
    expect(requests, ['/api/centers', '/api/centers/3/trainers']);
  });
}
