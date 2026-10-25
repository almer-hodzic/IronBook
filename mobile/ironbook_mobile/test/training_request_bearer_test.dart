import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';

import 'support/token_provider.dart';

const trainerJson = {
  'id': 9,
  'centerId': 3,
  'centerName': 'Ilidza',
  'centerLocation': 'Ilidza',
  'firstName': 'Aida',
  'lastName': 'Test',
  'fullName': 'Aida Test',
  'email': 'trainer@example.com',
  'phoneNumber': null,
  'biography': 'Strength coaching.',
};
const trainingJson = {
  'id': 15,
  'centerId': 3,
  'centerName': 'Ilidza',
  'trainerProfileId': 9,
  'trainerName': 'Aida Test',
  'memberProfileId': 7,
  'requestedStartAt': '2030-01-01T09:00:00Z',
  'durationMinutes': 60,
  'status': 'Pending',
  'fitnessGoal': 'Build Strength',
  'note': 'Session note',
  'createdAt': '2029-12-31T12:00:00Z',
};

void main() {
  Future<Object?> create(CenterApiService api) => api.createTrainingRequest(
    centerId: 3,
    trainerId: 9,
    requestedStartAt: DateTime.utc(2030, 1, 1, 9),
    fitnessGoal: 'Build Strength',
    note: 'Session note',
  );
  final protectedCalls = <String, Future<Object?> Function(CenterApiService)>{
    'Availability': (api) =>
        api.getTrainerAvailability(centerId: 3, trainerId: 9),
    'Training Request': create,
  };

  test('public Trainer list/details keep center/search paths, parsing and API ordering without a token', () async {
    final tokens = FakeAccessTokenProvider(null);
    final paths = <String>[];
    final api = CenterApiService(
      apiBaseUrl: 'http://localhost',
      accessTokenProvider: tokens,
      client: MockClient((request) async {
        expect(request.headers.containsKey('Authorization'), isFalse);
        paths.add(request.url.path);
        if (request.url.path.endsWith('/9')) {
          return http.Response(jsonEncode(trainerJson), 200);
        }
        expect(request.url.queryParameters, {'search': 'Aida & Test'});
        return http.Response(
          jsonEncode([
            trainerJson,
            {...trainerJson, 'id': 10, 'fullName': 'Second Trainer'},
          ]),
          200,
        );
      }),
    );
    final trainers = await api.getTrainersForCenter(3, search: ' Aida & Test ');
    expect(trainers.map((value) => value.id), [9, 10]);
    final trainer = await api.getTrainerForCenter(3, 9);
    expect(trainer.centerId, 3);
    expect(trainer.centerName, 'Ilidza');
    expect(trainer.centerLocation, 'Ilidza');
    expect(trainer.firstName, 'Aida');
    expect(trainer.lastName, 'Test');
    expect(trainer.fullName, 'Aida Test');
    expect(trainer.email, 'trainer@example.com');
    expect(trainer.phoneNumber, isNull);
    expect(trainer.biography, 'Strength coaching.');
    expect(paths, ['/api/centers/3/trainers', '/api/centers/3/trainers/9']);
    expect(tokens.reads, 0);
  });

  test(
    'public Trainer empty list and unavailable details stay unchanged',
    () async {
      final api = CenterApiService(
        apiBaseUrl: 'http://localhost',
        accessTokenProvider: FakeAccessTokenProvider(null),
        client: MockClient((request) async {
          expect(request.url.hasQuery, isFalse);
          return request.url.path.endsWith('/9')
              ? http.Response('', 404)
              : http.Response('[]', 200);
        }),
      );
      expect(await api.getTrainersForCenter(3, search: ' '), isEmpty);
      await expectLater(
        api.getTrainerForCenter(3, 9),
        throwsA(
          isA<CenterApiException>().having(
            (error) => error.message,
            'message',
            'Trainer is not available for this center.',
          ),
        ),
      );
    },
  );

  for (final withDate in [false, true]) {
    test(
      'availability adds current token and preserves seven days/slots (startDate=$withDate)',
      () async {
        final tokens = FakeAccessTokenProvider('first-token');
        final headers = <String?>[];
        final days = List.generate(7, (index) {
          final day = DateTime.utc(2030, 1, index + 1);
          final date = day.toIso8601String().substring(0, 10);
          return {
            'date': date,
            'dayLabel': 'Day ${index + 1}',
            'dateLabel': '${index + 1}',
            'monthLabel': 'Jan',
            'slots': [
              for (final status in ['Free', 'Booked', 'Unavailable'])
                {
                  'startsAt': day
                      .add(
                        Duration(
                          hours:
                              9 +
                              ['Free', 'Booked', 'Unavailable'].indexOf(status),
                        ),
                      )
                      .toIso8601String(),
                  'date': date,
                  'time': '09:00',
                  'period': 'AM',
                  'isAvailable': status == 'Free',
                  'status': status,
                },
            ],
          };
        });
        final api = CenterApiService(
          apiBaseUrl: 'http://10.0.2.2:5100',
          accessTokenProvider: tokens,
          client: MockClient((request) async {
            expect(request.method, 'GET');
            expect(request.url.path, '/api/centers/3/trainers/9/availability');
            expect(
              request.url.queryParameters,
              withDate ? {'startDate': '2030-01-01'} : isEmpty,
            );
            expect(request.body, isEmpty);
            headers.add(request.headers['Authorization']);
            return http.Response(jsonEncode(days), 200);
          }),
        );
        final result = await api.getTrainerAvailability(
          centerId: 3,
          trainerId: 9,
          startDate: withDate ? DateTime.utc(2030, 1, 1) : null,
        );
        expect(result, hasLength(7));
        for (var i = 0; i < result.length; i++) {
          expect(
            result[i].date,
            '2030-01-${(i + 1).toString().padLeft(2, '0')}',
          );
          expect(result[i].dayLabel, 'Day ${i + 1}');
          expect(result[i].dateLabel, '${i + 1}');
          expect(result[i].monthLabel, 'Jan');
          expect(result[i].slots.map((slot) => slot.status), [
            'Free',
            'Booked',
            'Unavailable',
          ]);
          expect(result[i].slots.map((slot) => slot.isAvailable), [
            true,
            false,
            false,
          ]);
          expect(
            result[i].slots.first.startsAt,
            DateTime.utc(2030, 1, i + 1, 9),
          );
          expect(result[i].slots.first.time, '09:00');
          expect(result[i].slots.first.period, 'AM');
          expect(result[i].slots.first.date, result[i].date);
        }
        tokens.token = 'second-token';
        await api.getTrainerAvailability(
          centerId: 3,
          trainerId: 9,
          startDate: withDate ? DateTime.utc(2030, 1, 1) : null,
        );
        expect(headers, ['Bearer first-token', 'Bearer second-token']);
      },
    );
  }

  for (final status in [200, 201]) {
    test(
      'Training Request $status sends Bearer with only business fields and preserves DTO',
      () async {
        final api = CenterApiService(
          apiBaseUrl: 'http://localhost',
          accessTokenProvider: FakeAccessTokenProvider(),
          client: MockClient((request) async {
            expect(
              request.url.path,
              '/api/centers/3/trainers/9/training-requests',
            );
            expect(request.method, 'POST');
            expect(
              request.headers['Authorization'],
              'Bearer fixture-access-token',
            );
            expect(request.headers['Content-Type'], 'application/json');
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body, {
              'requestedStartAt': '2030-01-01T09:00:00.000Z',
              'fitnessGoal': 'Build Strength',
              'note': 'Session note',
            });
            for (final field in [
              'memberProfileId',
              'memberId',
              'email',
              'username',
            ]) {
              expect(body.containsKey(field), isFalse);
            }
            return http.Response(jsonEncode(trainingJson), status);
          }),
        );
        final result = await api.createTrainingRequest(
          centerId: 3,
          trainerId: 9,
          requestedStartAt: DateTime.utc(2030, 1, 1, 9),
          fitnessGoal: 'Build Strength',
          note: 'Session note',
        );
        expect(result.id, 15);
        expect(result.centerId, 3);
        expect(result.centerName, 'Ilidza');
        expect(result.trainerProfileId, 9);
        expect(result.trainerName, 'Aida Test');
        expect(result.memberProfileId, 7);
        expect(result.requestedStartAt, DateTime.utc(2030, 1, 1, 9));
        expect(result.durationMinutes, 60);
        expect(result.status, 'Pending');
        expect(result.fitnessGoal, 'Build Strength');
        expect(result.note, 'Session note');
        expect(result.createdAt, DateTime.utc(2029, 12, 31, 12));
      },
    );
  }

  for (final entry in protectedCalls.entries) {
    for (final token in [null, '', 'Bearer malformed']) {
      test(
        '${entry.key} missing/malformed token fails before network ($token)',
        () async {
          var sent = false;
          final api = CenterApiService(
            apiBaseUrl: 'http://localhost',
            accessTokenProvider: FakeAccessTokenProvider(token),
            client: MockClient((_) async {
              sent = true;
              return http.Response('', 200);
            }),
          );
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
          expect(sent, isFalse);
        },
      );
    }
    test(
      '${entry.key} 401 is observable without clearing token, retry or auth navigation',
      () async {
        final tokens = FakeAccessTokenProvider();
        var requests = 0;
        final api = CenterApiService(
          apiBaseUrl: 'http://localhost',
          accessTokenProvider: tokens,
          client: MockClient((_) async {
            requests++;
            return http.Response('', 401);
          }),
        );
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
        expect(tokens.token, 'fixture-access-token');
        expect(requests, 1);
      },
    );
  }

  for (final status in [400, 404, 409]) {
    test(
      'Training Request $status retains existing business/validation feedback',
      () async {
        final api = CenterApiService(
          apiBaseUrl: 'http://localhost',
          accessTokenProvider: FakeAccessTokenProvider(),
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'errors': {
                  'Request': ['Existing request rejection.'],
                },
              }),
              status,
            ),
          ),
        );
        await expectLater(
          create(api),
          throwsA(
            isA<CenterApiException>().having(
              (error) => error.message,
              'message',
              'Existing request rejection.',
            ),
          ),
        );
      },
    );
  }

  test('availability 404 retains existing resource error', () async {
    final api = CenterApiService(
      apiBaseUrl: 'http://localhost',
      accessTokenProvider: FakeAccessTokenProvider(),
      client: MockClient((_) async => http.Response('', 404)),
    );
    await expectLater(
      api.getTrainerAvailability(centerId: 3, trainerId: 9),
      throwsA(
        isA<CenterApiException>().having(
          (error) => error.message,
          'message',
          'Trainer availability is not available for this center.',
        ),
      ),
    );
  });

  test('Centers and Trainer Dashboard remain non-Bearer', () async {
    final tokens = FakeAccessTokenProvider();
    final paths = <String>[];
    final api = CenterApiService(
      apiBaseUrl: 'http://localhost',
      accessTokenProvider: tokens,
      client: MockClient((request) async {
        expect(request.headers.containsKey('Authorization'), isFalse);
        paths.add(request.url.path);
        return http.Response('[]', 200);
      }),
    );
    await api.getCenters();
    await api.getTrainerDashboardRequests();
    expect(tokens.reads, 0);
    expect(paths, ['/api/centers', '/api/trainer/dashboard/coaching-requests']);
  });
}
