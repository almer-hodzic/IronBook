import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_auth/ironbook_auth.dart';
import 'package:ironbook_admin/services/bearer_http_client.dart';
import 'package:ironbook_admin/services/admin_center_api_service.dart';
import 'package:ironbook_admin/services/admin_trainer_api_service.dart';
import 'package:ironbook_admin/services/admin_membership_plan_api_service.dart';
import 'package:ironbook_admin/services/admin_group_training_api_service.dart';
import 'package:ironbook_admin/services/admin_coaching_request_api_service.dart';
import 'package:ironbook_admin/services/admin_payment_api_service.dart';
import 'package:ironbook_admin/services/admin_reports_api_service.dart';
import 'package:ironbook_admin/services/admin_check_in_api_service.dart';
import 'package:ironbook_admin/models/admin_center.dart';
import 'package:ironbook_admin/models/admin_trainer.dart';
import 'package:ironbook_admin/models/admin_membership_plan.dart';
import 'package:ironbook_admin/models/admin_group_training.dart';
import 'package:ironbook_admin/models/admin_payment.dart';
import 'package:ironbook_admin/models/admin_reports.dart';

import 'support/token_provider.dart';

typedef RunCall = Future<Object?> Function(http.Client, AccessTokenProvider);

class ApiCall {
  const ApiCall(
    this.name,
    this.path,
    this.run, {
    this.method = 'GET',
    this.query = const {},
    this.body,
  });
  final String name;
  final String path;
  final RunCall run;
  final String method;
  final Map<String, String> query;
  final Object? body;
}

int? status(Object error) => switch (error) {
  AdminCenterApiException e => e.statusCode,
  AdminTrainerApiException e => e.statusCode,
  AdminMembershipPlanApiException e => e.statusCode,
  AdminGroupTrainingApiException e => e.statusCode,
  AdminCoachingRequestApiException e => e.statusCode,
  AdminPaymentApiException e => e.statusCode,
  AdminReportsApiException e => e.statusCode,
  _ => null,
};

void main() {
  const center = AdminCenterWriteRequest(
    name: 'Test',
    location: 'Ilidza',
    capacity: 40,
    isActive: true,
    notes: 'Notes',
  );
  const trainer = AdminTrainerWriteRequest(
    firstName: 'Test',
    lastName: 'Trainer',
    email: 'trainer@example.com',
    isActive: true,
    centerIds: [3],
  );
  const plan = AdminMembershipPlanWriteRequest(
    name: 'Plan',
    monthlyPrice: 75.5,
    isActive: true,
    centerIds: [3],
  );
  final group = AdminGroupTrainingWriteRequest(
    name: 'Session',
    centerId: 3,
    trainerProfileId: 4,
    category: 'strength',
    difficulty: 'Intermediate',
    startsAt: DateTime.utc(2030, 1, 15, 10),
    durationMinutes: 60,
    capacity: 10,
    status: 'Active',
  );
  final filter = AdminReportFilter(
    fromDate: '2030-01-01',
    toDate: '2030-01-31',
    centerId: 3,
  );
  final calls = [
    ApiCall(
      'Centers list',
      '/api/admin/centers',
      (c, t) => AdminCenterApiService(
        client: c,
        accessTokenProvider: t,
      ).getCenters(search: ' Test & Center '),
      query: {'search': 'Test & Center'},
    ),
    ApiCall(
      'Center details',
      '/api/admin/centers/3',
      (c, t) =>
          AdminCenterApiService(client: c, accessTokenProvider: t).getCenter(3),
    ),
    ApiCall(
      'Center create',
      '/api/admin/centers',
      (c, t) => AdminCenterApiService(
        client: c,
        accessTokenProvider: t,
      ).createCenter(center),
      method: 'POST',
      body: center.toJson(),
    ),
    ApiCall(
      'Center update',
      '/api/admin/centers/3',
      (c, t) => AdminCenterApiService(
        client: c,
        accessTokenProvider: t,
      ).updateCenter(3, center),
      method: 'PUT',
      body: center.toJson(),
    ),
    ApiCall(
      'Trainers list',
      '/api/admin/trainers',
      (c, t) => AdminTrainerApiService(
        client: c,
        accessTokenProvider: t,
      ).getTrainers(search: ' Test '),
      query: {'search': 'Test'},
    ),
    ApiCall(
      'Trainer details',
      '/api/admin/trainers/4',
      (c, t) => AdminTrainerApiService(
        client: c,
        accessTokenProvider: t,
      ).getTrainer(4),
    ),
    ApiCall(
      'Trainer create',
      '/api/admin/trainers',
      (c, t) => AdminTrainerApiService(
        client: c,
        accessTokenProvider: t,
      ).createTrainer(trainer),
      method: 'POST',
      body: trainer.toJson(),
    ),
    ApiCall(
      'Trainer update',
      '/api/admin/trainers/4',
      (c, t) => AdminTrainerApiService(
        client: c,
        accessTokenProvider: t,
      ).updateTrainer(4, trainer),
      method: 'PUT',
      body: trainer.toJson(),
    ),
    ApiCall(
      'Plans list',
      '/api/admin/membership-plans',
      (c, t) => AdminMembershipPlanApiService(
        client: c,
        accessTokenProvider: t,
      ).getMembershipPlans(search: ' Plan '),
      query: {'search': 'Plan'},
    ),
    ApiCall(
      'Plan details',
      '/api/admin/membership-plans/5',
      (c, t) => AdminMembershipPlanApiService(
        client: c,
        accessTokenProvider: t,
      ).getMembershipPlan(5),
    ),
    ApiCall(
      'Plan create',
      '/api/admin/membership-plans',
      (c, t) => AdminMembershipPlanApiService(
        client: c,
        accessTokenProvider: t,
      ).createMembershipPlan(plan),
      method: 'POST',
      body: plan.toJson(),
    ),
    ApiCall(
      'Plan update',
      '/api/admin/membership-plans/5',
      (c, t) => AdminMembershipPlanApiService(
        client: c,
        accessTokenProvider: t,
      ).updateMembershipPlan(5, plan),
      method: 'PUT',
      body: plan.toJson(),
    ),
    ApiCall(
      'Groups list',
      '/api/admin/group-trainings',
      (c, t) => AdminGroupTrainingApiService(
        client: c,
        accessTokenProvider: t,
      ).getGroupTrainings(search: ' Session ', centerId: 3),
      query: {'search': 'Session', 'centerId': '3'},
    ),
    ApiCall(
      'Group details',
      '/api/admin/group-trainings/6',
      (c, t) => AdminGroupTrainingApiService(
        client: c,
        accessTokenProvider: t,
      ).getGroupTraining(6),
    ),
    ApiCall(
      'Group trainer options',
      '/api/admin/group-trainings/trainer-options',
      (c, t) => AdminGroupTrainingApiService(
        client: c,
        accessTokenProvider: t,
      ).getTrainerOptions(centerId: 3),
      query: {'centerId': '3'},
    ),
    ApiCall(
      'Group create',
      '/api/admin/group-trainings',
      (c, t) => AdminGroupTrainingApiService(
        client: c,
        accessTokenProvider: t,
      ).createGroupTraining(group),
      method: 'POST',
      body: group.toJson(),
    ),
    ApiCall(
      'Group update',
      '/api/admin/group-trainings/6',
      (c, t) => AdminGroupTrainingApiService(
        client: c,
        accessTokenProvider: t,
      ).updateGroupTraining(6, group),
      method: 'PUT',
      body: group.toJson(),
    ),
    ApiCall(
      'Coaching list',
      '/api/admin/coaching-requests',
      (c, t) => AdminCoachingRequestApiService(
        client: c,
        accessTokenProvider: t,
      ).getCoachingRequests(search: ' Member ', status: ' Pending '),
      query: {'search': 'Member', 'status': 'Pending'},
    ),
    for (final action in ['approve', 'reject', 'cancel'])
      ApiCall(
        'Coaching $action',
        '/api/admin/coaching-requests/8/$action',
        (c, t) {
          final api = AdminCoachingRequestApiService(
            client: c,
            accessTokenProvider: t,
          );
          return switch (action) {
            'approve' => api.approve(8),
            'reject' => api.reject(8),
            _ => api.cancel(8),
          };
        },
        method: 'POST',
        body: const <String, dynamic>{},
      ),
    ApiCall(
      'Coaching reassign',
      '/api/admin/coaching-requests/8/reassign-trainer',
      (c, t) => AdminCoachingRequestApiService(
        client: c,
        accessTokenProvider: t,
      ).reassignTrainer(8, 4),
      method: 'POST',
      body: const {'trainerProfileId': 4},
    ),
    ApiCall(
      'Coaching trainer options',
      '/api/admin/trainers',
      (c, t) => AdminCoachingRequestApiService(
        client: c,
        accessTokenProvider: t,
      ).getActiveTrainersForCenter(3),
    ),
    ApiCall(
      'Payments list',
      '/api/admin/payments',
      (c, t) =>
          AdminPaymentApiService(client: c, accessTokenProvider: t).getPayments(
            const AdminPaymentFilter(
              search: ' Member ',
              status: 'PendingReception',
              paymentMethod: 'Reception',
              centerId: 3,
            ),
          ),
      query: {
        'search': 'Member',
        'status': 'PendingReception',
        'paymentMethod': 'Reception',
        'centerId': '3',
      },
    ),
    ApiCall(
      'Payments centers',
      '/api/admin/centers',
      (c, t) => AdminPaymentApiService(
        client: c,
        accessTokenProvider: t,
      ).getCenters(),
    ),
    ApiCall(
      'Payment confirmation',
      '/api/admin/payments/12/confirm-reception',
      (c, t) => AdminPaymentApiService(
        client: c,
        accessTokenProvider: t,
      ).confirmReception(12),
      method: 'POST',
      body: const <String, dynamic>{},
    ),
    ApiCall(
      'Reports summary',
      '/api/admin/reports/summary',
      (c, t) => AdminReportsApiService(
        client: c,
        accessTokenProvider: t,
      ).getSummary(filter),
      query: filter.query,
    ),
    ApiCall(
      'Reports centers',
      '/api/admin/reports/centers',
      (c, t) => AdminReportsApiService(
        client: c,
        accessTokenProvider: t,
      ).getCenterActivity(filter),
      query: filter.query,
    ),
    ApiCall(
      'Reports filter centers',
      '/api/admin/centers',
      (c, t) => AdminReportsApiService(
        client: c,
        accessTokenProvider: t,
      ).getFilterCenters(),
    ),
  ];

  for (final call in calls) {
    test(
      '${call.name} sends Bearer and preserves method, route, query and payload',
      () async {
        var sent = 0;
        final client = MockClient((request) async {
          sent++;
          expect(request.method, call.method);
          expect(request.url.path, call.path);
          final pagedRoutes = [
            '/api/admin/centers',
            '/api/admin/trainers',
            '/api/admin/membership-plans',
            '/api/admin/group-trainings',
            '/api/admin/coaching-requests',
            '/api/admin/payments',
          ];
          final lookup = [
            'Coaching trainer options',
            'Payments centers',
            'Reports filter centers',
          ].contains(call.name);
          expect(request.url.queryParameters, {
            ...call.query,
            if (call.method == 'GET' && pagedRoutes.contains(call.path))
              'pageNumber': '1',
            if (lookup) 'pageSize': '100',
          });
          expect(
            request.headers['Authorization'],
            'Bearer fixture-access-token',
          );
          if (call.body == null) {
            expect(request.body, isEmpty);
          } else {
            expect(request.headers['Content-Type'], 'application/json');
            final body = jsonDecode(request.body) as Map;
            expect(body, call.body);
            expect(body.keys, isNot(contains('accountId')));
            expect(body.keys, isNot(contains('adminId')));
          }
          return http.Response(
            jsonEncode({
              'message': 'Existing business error.',
              'detail': 'Existing business error.',
            }),
            400,
          );
        });
        await expectLater(
          call.run(client, FakeAccessTokenProvider()),
          throwsA(predicate<Object>((e) => status(e) == 400)),
        );
        expect(sent, 1);
      },
    );
  }

  final representatives = [
    calls[0],
    calls[4],
    calls[8],
    calls[12],
    calls[17],
    calls[23],
    calls[26],
  ];
  for (final call in representatives) {
    for (final code in [401, 403, 404, 409]) {
      test(
        '${call.name} $code is observable without retry or session clearing',
        () async {
          var sent = 0;
          final tokens = FakeAccessTokenProvider();
          final client = MockClient((_) async {
            sent++;
            return http.Response('{}', code);
          });
          await expectLater(
            call.run(client, tokens),
            throwsA(predicate<Object>((e) => status(e) == code)),
          );
          expect(sent, 1);
          expect(tokens.token, 'fixture-access-token');
        },
      );
    }
    for (final token in [null, 'Bearer malformed']) {
      test(
        '${call.name} invalid token fails before network ($token)',
        () async {
          var sent = 0;
          final client = MockClient((_) async {
            sent++;
            return http.Response('[]', 200);
          });
          await expectLater(
            call.run(client, FakeAccessTokenProvider(token)),
            throwsA(
              predicate<Object>(
                (e) =>
                    status(e) == 401 &&
                    !e.toString().contains('Bearer malformed'),
              ),
            ),
          );
          expect(sent, 0);
        },
      );
    }
  }

  test('transport obtains token per request and preserves headers and body with one Authorization', () async {
    final tokens = FakeAccessTokenProvider('first-token');
    final seen = <String?>[];
    final client = BearerHttpClient(
      accessTokenProvider: tokens,
      client: MockClient((request) async {
        seen.add(request.headers['Authorization']);
        expect(
          request.headers.keys.where((k) => k.toLowerCase() == 'authorization'),
          hasLength(1),
        );
        expect(request.headers['X-Test'], 'keep');
        expect(request.body, '{"value":1}');
        return http.Response('', 204);
      }),
    );
    for (final token in ['first-token', 'second-token']) {
      tokens.token = token;
      final request =
          http.Request('PUT', Uri.parse('http://localhost/api/admin/centers/3'))
            ..headers.addAll({
              'Authorization': 'Bearer obsolete',
              'X-Test': 'keep',
              'Content-Type': 'application/json',
            })
            ..body = '{"value":1}';
      await client.send(request);
    }
    expect(seen, ['Bearer first-token', 'Bearer second-token']);
    expect(tokens.reads, 2);
  });

  for (final token in [null, '', 'Bearer malformed', 'token\nprivate']) {
    test('transport rejects invalid credential safely ($token)', () async {
      var sent = 0;
      final client = BearerHttpClient(
        accessTokenProvider: FakeAccessTokenProvider(token),
        client: MockClient((_) async {
          sent++;
          return http.Response('', 200);
        }),
      );
      await expectLater(
        client.get(Uri.parse('http://localhost')),
        throwsA(
          isA<AuthenticationRequiredException>().having(
            (e) => e.toString(),
            'safe error',
            'Authentication is required.',
          ),
        ),
      );
      expect(sent, 0);
    });
  }

  test('Admin Check-In sends Bearer and preserves QR payload', () async {
    var sent = 0;
    final api = AdminCheckInApiService(
      accessTokenProvider: FakeAccessTokenProvider(),
      client: MockClient((request) async {
        sent++;
        expect(request.method, 'POST');
        expect(request.url.path, '/api/check-ins/validate');
        expect(request.headers['Authorization'], 'Bearer fixture-access-token');
        expect(jsonDecode(request.body), {
          'qrAccessToken': 'fixture-qr-token',
          'centerId': 3,
        });
        return http.Response('{}', 400);
      }),
    );
    await expectLater(
      api.validateCheckIn(qrAccessToken: 'fixture-qr-token', centerId: 3),
      throwsA(isA<AdminCheckInApiException>()),
    );
    expect(sent, 1);
  });
}
