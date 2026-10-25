import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';
import 'package:ironbook_mobile/screens/member_progress_log_screen.dart';

import 'support/token_provider.dart';
import 'training_request_bearer_test.dart' show trainingJson;

const report = {
  'id': 10,
  'trainingDate': '2030-02-03T10:00:00Z',
  'trainerName': 'Trainer',
  'centerName': 'Ilidza',
  'reportNotes': 'Session notes',
  'exercises': [
    {
      'exerciseName': 'Squat',
      'sets': 3,
      'reps': 8,
      'weight': 40,
      'notes': 'Controlled',
    },
    {
      'exerciseName': 'Stretch',
      'sets': 1,
      'reps': 5,
      'weight': null,
      'notes': null,
    },
  ],
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
    'My Trainings': (api) => api.getMyTrainings(),
    'Cancellation': (api) => api.cancelMyTraining(15),
    'Progress Log': (api) => api.getMemberProgressLog(),
  };

  test(
    'My Trainings Bearer preserves status filter, API order and complete DTO',
    () async {
      final tokens = FakeAccessTokenProvider();
      final queries = <Map<String, String>>[];
      final api = apiFor((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/member/my-trainings');
        expect(request.headers['Authorization'], 'Bearer ${tokens.token}');
        expect(request.body, isEmpty);
        queries.add(request.url.queryParameters);
        return http.Response(
          jsonEncode([
            for (final status in [
              'Pending',
              'Approved',
              'Rejected',
              'Cancelled',
            ])
              {
                ...trainingJson,
                'id':
                    20 -
                    [
                      'Pending',
                      'Approved',
                      'Rejected',
                      'Cancelled',
                    ].indexOf(status),
                'status': status,
              },
          ]),
          200,
        );
      }, tokens);
      final result = await api.getMyTrainings();
      expect(result.map((row) => row.id), [20, 19, 18, 17]);
      expect(result.map((row) => row.status), [
        'Pending',
        'Approved',
        'Rejected',
        'Cancelled',
      ]);
      final row = result.first;
      expect(row.centerId, 3);
      expect(row.centerName, 'Ilidza');
      expect(row.trainerProfileId, 9);
      expect(row.trainerName, 'Aida Test');
      expect(row.memberProfileId, 7);
      expect(row.requestedStartAt, DateTime.utc(2030, 1, 1, 9));
      expect(row.durationMinutes, 60);
      expect(row.fitnessGoal, 'Build Strength');
      expect(row.note, 'Session note');
      expect(row.createdAt, DateTime.utc(2029, 12, 31, 12));
      tokens.token = 'new-token';
      await api.getMyTrainings(status: 'Approved');
      expect(queries, [
        {},
        {'status': 'Approved'},
      ]);
      expect(tokens.reads, 2);
    },
  );

  for (final name in ['My Trainings', 'Progress Log']) {
    test('$name retains empty list', () async {
      final api = apiFor((_) async => http.Response('[]', 200));
      expect(await calls[name]!(api), isEmpty);
    });
  }

  test(
    'cancellation sends resource ID and empty business body, parses Cancelled',
    () async {
      final api = apiFor((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/member/my-trainings/15/cancel');
        expect(request.url.hasQuery, isFalse);
        expect(request.headers['Authorization'], 'Bearer fixture-access-token');
        expect(request.headers['Content-Type'], 'application/json');
        expect(jsonDecode(request.body), isEmpty);
        return http.Response(
          jsonEncode({...trainingJson, 'status': 'Cancelled'}),
          200,
        );
      });
      final result = await api.cancelMyTraining(15);
      expect(result.id, 15);
      expect(result.status, 'Cancelled');
      expect(result.centerName, 'Ilidza');
      expect(result.note, 'Session note');
    },
  );

  for (final code in [404, 409]) {
    test('cancellation $code retains existing error mapping', () async {
      final api = apiFor((_) async => http.Response('', code));
      await expectLater(
        api.cancelMyTraining(15),
        throwsA(
          isA<CenterApiException>().having(
            (error) => error.message,
            'message',
            code == 404
                ? 'This training request is no longer available. Refresh your trainings.'
                : 'This training can no longer be cancelled. Refresh your trainings.',
          ),
        ),
      );
    });
  }

  for (final filter in ['none', 'from', 'to', 'both', 'reversed']) {
    test(
      'Progress Log Bearer preserves $filter calendar filters and report parsing/order',
      () async {
        final from =
            filter == 'from' || filter == 'both' || filter == 'reversed'
            ? DateTime(2030, 2, 3, 23, 59)
            : null;
        final to = filter == 'to' || filter == 'both' || filter == 'reversed'
            ? DateTime(2030, 2, filter == 'reversed' ? 1 : 4, 1)
            : null;
        final api = apiFor((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/member/progress-log');
          expect(
            request.headers['Authorization'],
            'Bearer fixture-access-token',
          );
          expect(request.body, isEmpty);
          expect(request.url.queryParameters, {
            if (from != null) 'fromDate': '2030-02-03',
            if (to != null)
              'toDate': filter == 'reversed' ? '2030-02-01' : '2030-02-04',
          });
          // Existing service forwards reversed ranges; screen/server validate them.
          if (filter == 'reversed') return http.Response('', 400);
          return http.Response(
            jsonEncode([
              {...report, 'id': 8, 'trainingDate': '2030-01-01T10:00:00Z'},
              report,
              {...report, 'id': 11},
            ]),
            200,
          );
        });
        if (filter == 'reversed') {
          await expectLater(
            api.getMemberProgressLog(fromDate: from, toDate: to),
            throwsA(
              isA<CenterApiException>().having(
                (e) => e.message,
                'message',
                'Progress log could not be loaded.',
              ),
            ),
          );
          return;
        }
        final reports = await api.getMemberProgressLog(
          fromDate: from,
          toDate: to,
        );
        expect(reports.map((row) => row.id), [11, 10, 8]);
        final row = reports.first;
        expect(row.trainingDate, DateTime.utc(2030, 2, 3, 10));
        expect(row.trainerName, 'Trainer');
        expect(row.centerName, 'Ilidza');
        expect(row.reportNotes, 'Session notes');
        expect(row.exercises, hasLength(2));
        final exercise = row.exercises.first;
        expect(exercise.exerciseName, 'Squat');
        expect(exercise.sets, 3);
        expect(exercise.reps, 8);
        expect(exercise.weight, 40.0);
        expect(exercise.notes, 'Controlled');
        expect(row.exercises.last.weight, isNull);
        expect(row.exercises.last.notes, isNull);
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
                (e) => e.statusCode,
                'status',
                401,
              ),
            ),
          );
          expect(requests, 0);
        },
      );
    }
    test(
      '${entry.key} backend 401 observable with no retry or token clearing',
      () async {
        var requests = 0;
        final tokens = FakeAccessTokenProvider();
        final api = apiFor((_) async {
          requests++;
          return http.Response('', 401);
        }, tokens);
        await expectLater(
          entry.value(api),
          throwsA(
            isA<CenterApiException>().having(
              (e) => e.statusCode,
              'status',
              401,
            ),
          ),
        );
        expect(requests, 1);
        expect(tokens.token, 'fixture-access-token');
      },
    );
  }

  testWidgets(
    'Progress Log rejects reversed dates before another request and clear restores loading',
    (tester) async {
      var requests = 0;
      final api = apiFor((_) async {
        requests++;
        return http.Response('[]', 200);
      });
      await tester.binding.setSurfaceSize(const Size(600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: MemberProgressLogScreen(centerApiService: api)),
      );
      await tester.pumpAndSettle();
      expect(requests, 1);
      await tester.tap(find.text('From: Any date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(requests, 2);
      await tester.tap(find.text('To: Any date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('10').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('From date cannot be after To date.'), findsOneWidget);
      expect(requests, 2);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(requests, 3);
      expect(find.text('From date cannot be after To date.'), findsNothing);
    },
  );

  test('Trainer clients still make requests without Bearer', () async {
    final tokens = FakeAccessTokenProvider(null);
    var requests = 0;
    final api = apiFor((request) async {
      requests++;
      expect(request.headers.containsKey('Authorization'), isFalse);
      return http.Response('', 404);
    }, tokens);
    final unmigrated = <Future<Object?> Function()>[
      () => api.getTrainerDashboardRequests(),
      () => api.getTrainerClientDetails(5),
      () => api.createTrainingReport(
        trainingRequestId: 5,
        trainingDate: DateTime.utc(2030),
        exercises: [],
      ),
    ];
    for (final call in unmigrated) {
      await expectLater(call(), throwsA(isA<CenterApiException>()));
    }
    expect(requests, unmigrated.length);
    expect(tokens.reads, 0);
  });
}
