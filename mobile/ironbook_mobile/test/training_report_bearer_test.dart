import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';

import 'support/token_provider.dart';

const exercises = [
  {
    'exerciseName': 'Squat',
    'sets': 3,
    'reps': 8,
    'weight': 42.5,
    'notes': 'Controlled',
  },
  {
    'exerciseName': 'Stretch',
    'sets': 1,
    'reps': 5,
    'weight': null,
    'notes': null,
  },
];

void main() {
  CenterApiService apiFor(
    Future<http.Response> Function(http.Request) handler, [
    FakeAccessTokenProvider? tokens,
  ]) => CenterApiService(
    apiBaseUrl: 'http://localhost',
    accessTokenProvider: tokens ?? FakeAccessTokenProvider(),
    client: MockClient(handler),
  );
  Future<Object?> create(
    CenterApiService api, {
    String? notes = ' Report notes ',
  }) => api.createTrainingReport(
    trainingRequestId: 8,
    trainingDate: DateTime.parse('2030-01-15T12:00:00+02:00'),
    notes: notes,
    exercises: exercises,
  );

  for (final notes in [null, ' Report notes ']) {
    test(
      'Bearer POST preserves complete business payload and successful DTO (notes=$notes)',
      () async {
        final api = apiFor((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/trainer/training-reports');
          expect(request.url.hasQuery, isFalse);
          expect(
            request.headers['Authorization'],
            'Bearer fixture-access-token',
          );
          expect(request.headers['Content-Type'], 'application/json');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body, {
            'trainingRequestId': 8,
            'trainingDate': '2030-01-15T10:00:00.000Z',
            'notes': notes,
            'exercises': exercises,
          });
          for (final field in [
            'trainerProfileId',
            'trainerId',
            'email',
            'username',
            'memberProfileId',
            'memberId',
          ]) {
            expect(body.containsKey(field), isFalse);
          }
          return http.Response(
            jsonEncode({
              'id': 19,
              'trainingRequestId': 8,
              'trainerProfileId': 3,
              'memberProfileId': 4,
              'centerId': 7,
              'trainingDate': '2030-01-15T10:00:00Z',
              'notes': notes,
              'createdAt': '2030-01-16T09:00:00Z',
              'exercises': [
                for (var i = 0; i < exercises.length; i++)
                  {...exercises[i], 'id': i + 20},
              ],
            }),
            201,
          );
        });
        final result = await api.createTrainingReport(
          trainingRequestId: 8,
          trainingDate: DateTime.parse('2030-01-15T12:00:00+02:00'),
          notes: notes,
          exercises: exercises,
        );
        expect(result.id, 19);
        expect(result.trainingRequestId, 8);
        expect(result.trainerProfileId, 3);
        expect(result.memberProfileId, 4);
        expect(result.centerId, 7);
        expect(result.trainingDate, DateTime.utc(2030, 1, 15, 10));
        expect(result.createdAt, DateTime.utc(2030, 1, 16, 9));
        expect(result.notes, notes);
        expect(result.exercises, hasLength(2));
        final row = result.exercises.first;
        expect(row.id, 20);
        expect(row.exerciseName, 'Squat');
        expect(row.sets, 3);
        expect(row.reps, 8);
        expect(row.weight, 42.5);
        expect(row.notes, 'Controlled');
        expect(result.exercises.last.id, 21);
        expect(result.exercises.last.weight, isNull);
        expect(result.exercises.last.notes, isNull);
      },
    );
  }

  for (final token in [null, '', 'Bearer malformed']) {
    test('missing/malformed token $token fails before network', () async {
      var requests = 0;
      final api = apiFor((_) async {
        requests++;
        return http.Response('', 500);
      }, FakeAccessTokenProvider(token));
      await expectLater(
        create(api),
        throwsA(
          isA<CenterApiException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
      expect(requests, 0);
    });
  }

  for (final code in [401, 403]) {
    test(
      '$code is observable with fresh token reads and no retry or logout',
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
            create(api),
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

  final errors = {
    400: 'Exercise name is required.',
    404: 'Training request was not found.',
    409: 'A training report already exists for this request.',
  };
  for (final entry in errors.entries) {
    test(
      '${entry.key} retains validation/ownership/duplicate feedback and exposes status',
      () async {
        final api = apiFor(
          (_) async => http.Response(
            jsonEncode({
              'errors': {
                'Request': [entry.value],
              },
            }),
            entry.key,
          ),
        );
        await expectLater(
          create(api),
          throwsA(
            isA<CenterApiException>()
                .having((e) => e.statusCode, 'status', entry.key)
                .having((e) => e.message, 'message', entry.value),
          ),
        );
      },
    );
  }

  test('Approved requirement conflict retains existing feedback', () async {
    final api = apiFor(
      (_) async => http.Response(
        jsonEncode({
          'errors': {
            'Request': ['Only approved training requests can have reports.'],
          },
        }),
        409,
      ),
    );
    await expectLater(
      create(api),
      throwsA(
        isA<CenterApiException>()
            .having((e) => e.statusCode, 'status', 409)
            .having(
              (e) => e.message,
              'message',
              'Only approved training requests can have reports.',
            ),
      ),
    );
  });

  test('non-auth failure retains existing save error', () async {
    final api = apiFor((_) async => http.Response('', 500));
    await expectLater(
      create(api),
      throwsA(
        isA<CenterApiException>()
            .having((e) => e.statusCode, 'status', 500)
            .having(
              (e) => e.message,
              'message',
              'Training report could not be saved.',
            ),
      ),
    );
  });

  test('Dashboard, Client Details and Member calls still use Bearer', () async {
    final paths = <String>[];
    final api = apiFor((request) async {
      expect(request.method, 'GET');
      expect(request.headers['Authorization'], 'Bearer fixture-access-token');
      paths.add(request.url.path);
      return http.Response('', 401);
    });
    for (final call in <Future<Object?> Function()>[
      () => api.getTrainerDashboardRequests(),
      () => api.getTrainerClientDetails(8),
      () => api.getMemberNotifications(),
    ]) {
      await expectLater(
        call(),
        throwsA(
          isA<CenterApiException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
    }
    expect(paths, [
      '/api/trainer/dashboard/coaching-requests',
      '/api/trainer/dashboard/coaching-requests/8',
      '/api/member/notifications',
    ]);
  });
}
