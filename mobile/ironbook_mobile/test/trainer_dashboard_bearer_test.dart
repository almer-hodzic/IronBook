import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';

import 'support/token_provider.dart';

const requestJson = {
  'id': 8,
  'memberName': 'Member One',
  'centerName': 'Ilidza',
  'requestedStartAt': '2030-01-15T10:00:00Z',
  'durationMinutes': 60,
  'status': 'Approved',
  'createdAt': '2030-01-01T12:00:00Z',
};

void main() {
  CenterApiService apiFor(
    Future<http.Response> Function(http.Request) handler, [
    FakeAccessTokenProvider? tokens,
  ]) => CenterApiService(
    apiBaseUrl: 'http://localhost',
    accessTokenProvider: tokens ?? FakeAccessTokenProvider(),
    client: MockClient(handler),
  );

  final calls = <String, Future<Object?> Function(CenterApiService)>{
    'Dashboard': (api) => api.getTrainerDashboardRequests(),
    'Client Details': (api) => api.getTrainerClientDetails(8),
  };

  test(
    'Dashboard Bearer GET preserves Approved data and API ordering',
    () async {
      final api = apiFor((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/trainer/dashboard/coaching-requests');
        expect(request.url.hasQuery, isFalse);
        expect(request.body, isEmpty);
        expect(request.headers['Authorization'], 'Bearer fixture-access-token');
        return http.Response(
          jsonEncode([
            requestJson,
            {...requestJson, 'id': 3},
          ]),
          200,
        );
      });
      final rows = await api.getTrainerDashboardRequests();
      expect(rows.map((row) => row.id), [8, 3]);
      final row = rows.first;
      expect(row.memberName, 'Member One');
      expect(row.centerName, 'Ilidza');
      expect(row.requestedStartAt, DateTime.utc(2030, 1, 15, 10));
      expect(row.durationMinutes, 60);
      expect(row.status, 'Approved');
      expect(row.createdAt, DateTime.utc(2030, 1, 1, 12));
    },
  );

  test('Dashboard retains empty-list behavior', () async {
    final api = apiFor((_) async => http.Response('[]', 200));
    expect(await api.getTrainerDashboardRequests(), isEmpty);
  });

  for (final hasReport in [false, true]) {
    test(
      'Client Details preserves request ID, notes and HasTrainingReport=$hasReport',
      () async {
        final api = apiFor((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/api/trainer/dashboard/coaching-requests/8',
          );
          // Only the target request ID is sent; no acting-Trainer selector.
          expect(request.url.hasQuery, isFalse);
          expect(request.body, isEmpty);
          expect(
            request.headers['Authorization'],
            'Bearer fixture-access-token',
          );
          return http.Response(
            jsonEncode({
              ...requestJson,
              'fitnessGoal': 'Build Strength',
              'note': 'Original notes',
              'hasTrainingReport': hasReport,
            }),
            200,
          );
        });
        final result = await api.getTrainerClientDetails(8);
        expect(result.id, 8);
        expect(result.memberName, 'Member One');
        expect(result.centerName, 'Ilidza');
        expect(result.requestedStartAt, DateTime.utc(2030, 1, 15, 10));
        expect(result.durationMinutes, 60);
        expect(result.status, 'Approved');
        expect(result.createdAt, DateTime.utc(2030, 1, 1, 12));
        expect(result.fitnessGoal, 'Build Strength');
        expect(result.note, 'Original notes');
        expect(result.hasTrainingReport, hasReport);
      },
    );
  }

  for (final entry in calls.entries) {
    for (final token in [null, '', 'Bearer malformed']) {
      test(
        '${entry.key} missing/malformed token $token fails before network',
        () async {
          var requests = 0;
          final api = apiFor((_) async {
            requests++;
            return http.Response('', 500);
          }, FakeAccessTokenProvider(token));
          await expectLater(
            entry.value(api),
            throwsA(
              isA<CenterApiException>().having(
                (error) => error.statusCode,
                'status',
                401,
              ),
            ),
          );
          expect(requests, 0);
        },
      );
    }
    for (final code in [401, 403]) {
      test(
        '${entry.key} $code remains observable using current token without retry/logout',
        () async {
          final tokens = FakeAccessTokenProvider('first-token');
          final headers = <String?>[];
          final api = apiFor((request) async {
            headers.add(request.headers['Authorization']);
            return http.Response('Private server detail', code);
          }, tokens);
          for (final token in ['first-token', 'second-token']) {
            tokens.token = token;
            await expectLater(
              entry.value(api),
              throwsA(
                isA<CenterApiException>()
                    .having((e) => e.statusCode, 'status', code)
                    .having(
                      (e) => e.toString(),
                      'safe feedback',
                      isNot(contains('Private server detail')),
                    ),
              ),
            );
            expect(tokens.token, token);
          }
          expect(headers, ['Bearer first-token', 'Bearer second-token']);
          expect(tokens.reads, 2);
        },
      );
    }
    test('${entry.key} existing server error message is preserved', () async {
      final api = apiFor((_) async => http.Response('', 500));
      await expectLater(
        entry.value(api),
        throwsA(
          isA<CenterApiException>()
              .having((e) => e.statusCode, 'status', 500)
              .having(
                (e) => e.message,
                'message',
                entry.key == 'Dashboard'
                    ? 'Trainer dashboard requests could not be loaded.'
                    : 'Client details could not be loaded.',
              ),
        ),
      );
    });
  }

  test(
    'Client Details 404 retains existing message and exposes HTTP status',
    () async {
      final api = apiFor((_) async => http.Response('', 404));
      await expectLater(
        api.getTrainerClientDetails(8),
        throwsA(
          isA<CenterApiException>()
              .having((e) => e.statusCode, 'status', 404)
              .having(
                (e) => e.message,
                'message',
                'Client details could not be found.',
              ),
        ),
      );
    },
  );

  test('Training Report remains non-Bearer with unchanged payload; Member call still uses Bearer', () async {
    final tokens = FakeAccessTokenProvider();
    var requests = 0;
    final api = apiFor((request) async {
      requests++;
      if (request.url.path == '/api/trainer/training-reports') {
        expect(request.method, 'POST');
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(jsonDecode(request.body), {
          'trainingRequestId': 8,
          'trainingDate': '2030-01-15T10:00:00.000Z',
          'notes': 'Report notes',
          'exercises': [],
        });
        return http.Response('', 400);
      }
      expect(request.url.path, '/api/member/notifications');
      expect(request.headers['Authorization'], 'Bearer fixture-access-token');
      return http.Response('[]', 200);
    }, tokens);
    await expectLater(
      api.createTrainingReport(
        trainingRequestId: 8,
        trainingDate: DateTime.utc(2030, 1, 15, 10),
        notes: 'Report notes',
        exercises: [],
      ),
      throwsA(isA<CenterApiException>()),
    );
    expect(tokens.reads, 0);
    expect(await api.getMemberNotifications(), isEmpty);
    expect(tokens.reads, 1);
    expect(requests, 2);
  });
}
