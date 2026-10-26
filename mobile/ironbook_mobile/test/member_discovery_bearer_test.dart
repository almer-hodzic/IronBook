import 'support/paged_fixture.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';

import 'member_notifications_test.dart' show notification;
import 'recommendations_test.dart' show responseData;
import 'support/token_provider.dart';

const groupJson = {
  'id': 22,
  'centerId': 7,
  'centerName': 'Selected center',
  'name': 'Strength session',
  'description': 'Session description',
  'category': 'strength',
  'difficulty': 'Intermediate',
  'startsAt': '2030-01-15T10:00:00Z',
  'durationMinutes': 60,
  'capacity': 10,
  'enrolledCount': 10,
  'availableSpots': 0,
  'status': 'Active',
  'trainerName': 'Trainer One',
  'includes': 'Equipment',
  'whoFor': 'Members',
  'isEnrolled': true,
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
    'Recommendations': (api) => api.getRecommendationsForCenter(7),
    'Notifications': (api) => api.getMemberNotifications(),
    'Mark read': (api) => api.markNotificationRead(5),
    'Group list': (api) => api.getGroupTrainingsForCenter(7),
    'Group details': (api) => api.getGroupTrainingForCenter(7, 22),
    'Enrollment': (api) =>
        api.enrollGroupTraining(centerId: 7, groupTrainingId: 22),
  };

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
      '${entry.key} uses current Bearer token; 401 is observable without retry or logout',
      () async {
        final tokens = FakeAccessTokenProvider('first-token');
        final headers = <String?>[];
        final api = apiFor((request) async {
          headers.add(request.headers['Authorization']);
          return http.Response('', 401);
        }, tokens);
        for (final token in ['first-token', 'second-token']) {
          tokens.token = token;
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
          expect(tokens.token, token);
        }
        expect(headers, ['Bearer first-token', 'Bearer second-token']);
        expect(tokens.reads, 2);
      },
    );
  }

  for (final personalized in [true, false]) {
    test(
      'recommendations preserve center, scores, categories and cold start ($personalized)',
      () async {
        final api = apiFor((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/member/centers/7/recommendations');
          expect(request.url.hasQuery, isFalse);
          expect(request.body, isEmpty);
          expect(
            request.headers['Authorization'],
            'Bearer fixture-access-token',
          );
          final data = responseData(personalized: personalized);
          final trainers = data['trainers'] as List;
          trainers.add(<String, Object?>{
            ...trainers.first as Map<String, Object?>,
            'id': 12,
          });
          return http.Response(jsonEncode(data), 200);
        });
        final result = await api.getRecommendationsForCenter(7);
        expect(result.centerId, 7);
        expect(result.centerName, 'Selected center');
        expect(result.isPersonalized, personalized);
        expect(result.trainers.map((t) => t.id), [11, 12]);
        final trainer = result.trainers.first;
        expect(trainer.name, 'Trainer One');
        expect(trainer.categories, ['strength']);
        expect(trainer.similarity, personalized ? 0.75 : isNull);
        expect(trainer.approvedCoachingRequestCount, 3);
        final group = result.groupTrainings.single;
        expect(group.id, 22);
        expect(group.name, 'Session One');
        expect(group.trainerName, 'Trainer One');
        expect(group.category, 'conditioning');
        expect(group.startsAt, DateTime.utc(2030, 1, 15, 10));
        expect(group.capacity, 10);
        expect(group.enrollmentCount, 4);
        expect(group.fillRatio, 0.4);
        expect(group.similarity, personalized ? 0.5 : isNull);
      },
    );
  }

  test('notifications preserve newest-first, UTC timestamps, title/message and unread state', () async {
    final api = apiFor((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/member/notifications');
      expect(request.url.queryParameters, {
        'pageNumber': '1',
        'pageSize': '20',
      });
      expect(request.body, isEmpty);
      expect(request.headers['Authorization'], 'Bearer fixture-access-token');
      return http.Response(
        jsonEncode(
          paged([
            notification(id: 3),
            notification(id: 2, read: true),
            notification(id: 1, date: '2030-01-14T10:00:00'),
          ]),
        ),
        200,
      );
    });
    final rows = (await api.getMemberNotifications()).items;
    expect(rows.map((n) => n.id), [3, 2, 1]);
    expect(rows.map((n) => n.isRead), [false, true, false]);
    expect(rows.where((n) => !n.isRead), hasLength(2));
    expect(rows.first.createdAt, DateTime.utc(2030, 1, 15, 10));
    expect(rows.first.title, 'Coaching request 3');
    expect(rows.first.message, 'Your coaching request was approved.');
  });

  test('mark-read retains ID, empty body, confirmed read response and repeated read', () async {
    final api = apiFor((request) async {
      expect(request.method, 'PUT');
      expect(request.url.path, '/api/member/notifications/5/read');
      expect(request.url.hasQuery, isFalse);
      expect(jsonDecode(request.body), <String, dynamic>{});
      expect(request.headers['Authorization'], 'Bearer fixture-access-token');
      return http.Response(jsonEncode(notification(id: 5, read: true)), 200);
    });
    for (var i = 0; i < 2; i++) {
      final result = await api.markNotificationRead(5);
      expect(result.id, 5);
      expect(result.isRead, isTrue);
    }
  });

  test('missing notification preserves existing error', () async {
    final api = apiFor((_) async => http.Response('', 404));
    await expectLater(
      api.markNotificationRead(5),
      throwsA(
        isA<CenterApiException>().having(
          (e) => e.message,
          'message',
          'This notification is no longer available. Refresh the list.',
        ),
      ),
    );
  });

  for (final search in [null, ' ', ' strength & recovery ']) {
    test(
      'group list preserves search serialization and API order ($search)',
      () async {
        final api = apiFor((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/centers/7/group-trainings');
          expect(request.url.queryParameters, {
            'pageNumber': '1',
            'pageSize': '20',
            if (search != null && search.trim().isNotEmpty)
              'search': 'strength & recovery',
          });
          expect(request.body, isEmpty);
          expect(
            request.headers['Authorization'],
            'Bearer fixture-access-token',
          );
          return http.Response(
            jsonEncode(
              paged([
                groupJson,
                {
                  ...groupJson,
                  'id': 21,
                  'isEnrolled': false,
                  'enrolledCount': 4,
                  'availableSpots': 6,
                },
              ]),
            ),
            200,
          );
        });
        final rows = (await api.getGroupTrainingsForCenter(
          7,
          search: search,
        )).items;
        expect(rows.map((g) => g.id), [22, 21]);
        expect(rows.map((g) => g.isEnrolled), [true, false]);
        expect(rows.map((g) => g.availableSpots), [0, 6]);
        expect(rows.first.status, 'Active');
        expect(rows.first.enrolledCount, 10);
        expect(rows.first.capacity, 10);
      },
    );
  }

  test('group details retain full enrolled-session DTO', () async {
    final api = apiFor((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/centers/7/group-trainings/22');
      expect(request.url.hasQuery, isFalse);
      expect(request.body, isEmpty);
      expect(request.headers['Authorization'], 'Bearer fixture-access-token');
      return http.Response(jsonEncode(groupJson), 200);
    });
    final result = await api.getGroupTrainingForCenter(7, 22);
    expect(result.id, 22);
    expect(result.centerId, 7);
    expect(result.centerName, 'Selected center');
    expect(result.name, 'Strength session');
    expect(result.description, 'Session description');
    expect(result.category, 'strength');
    expect(result.difficulty, 'Intermediate');
    expect(result.startsAt, DateTime.utc(2030, 1, 15, 10));
    expect(result.durationMinutes, 60);
    expect(result.capacity, 10);
    expect(result.enrolledCount, 10);
    expect(result.availableSpots, 0);
    expect(result.isEnrolled, isTrue);
    expect(result.status, 'Active');
    expect(result.trainerName, 'Trainer One');
    expect(result.includes, 'Equipment');
    expect(result.whoFor, 'Members');
  });

  for (final status in [200, 201]) {
    test(
      'enrollment $status preserves empty existing payload and response',
      () async {
        final api = apiFor((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/centers/7/group-trainings/22/enroll');
          expect(request.url.hasQuery, isFalse);
          // Existing mobile contract sends {}, not an acting-Member selector.
          expect(jsonDecode(request.body), <String, dynamic>{});
          expect(
            request.headers['Authorization'],
            'Bearer fixture-access-token',
          );
          return http.Response(
            jsonEncode({
              'id': 99,
              'groupTrainingId': 22,
              'memberProfileId': 4,
              'status': 'Active',
              'enrolledAt': '2030-01-01T10:00:00Z',
            }),
            status,
          );
        });
        final result = await api.enrollGroupTraining(
          centerId: 7,
          groupTrainingId: 22,
        );
        expect(result.id, 99);
        expect(result.groupTrainingId, 22);
        expect(result.memberProfileId, 4);
        expect(result.status, 'Active');
        expect(result.enrolledAt, DateTime.utc(2030, 1, 1, 10));
      },
    );
  }

  for (final code in [400, 404, 409]) {
    test('enrollment $code preserves business rejection feedback', () async {
      final api = apiFor(
        (_) async => http.Response(
          jsonEncode({'message': 'Existing business rejection.'}),
          code,
        ),
      );
      await expectLater(
        api.enrollGroupTraining(centerId: 7, groupTrainingId: 22),
        throwsA(
          isA<CenterApiException>().having(
            (e) => e.message,
            'message',
            'Group training enrollment was rejected.',
          ),
        ),
      );
    });
  }

  test(
    'empty recommendations, notifications and group list remain empty',
    () async {
      final api = apiFor(
        (request) async => http.Response(
          request.url.path.endsWith('/recommendations')
              ? jsonEncode(responseData(empty: true, personalized: false))
              : jsonEncode(paged([])),
          200,
        ),
      );
      final recommendations = await api.getRecommendationsForCenter(7);
      expect(recommendations.trainers, isEmpty);
      expect(recommendations.groupTrainings, isEmpty);
      expect(recommendations.isPersonalized, isFalse);
      expect((await api.getMemberNotifications()).items, isEmpty);
      expect((await api.getGroupTrainingsForCenter(7)).items, isEmpty);
    },
  );
}
