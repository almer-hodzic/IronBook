import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_admin/models/paged_result.dart';
import 'package:ironbook_admin/models/admin_payment.dart';
import 'package:ironbook_admin/screens/centers_management_screen.dart';
import 'package:ironbook_admin/screens/membership_plans_screen.dart';
import 'package:ironbook_admin/services/admin_center_api_service.dart';
import 'package:ironbook_admin/services/admin_trainer_api_service.dart';
import 'package:ironbook_admin/services/admin_membership_plan_api_service.dart';
import 'package:ironbook_admin/services/admin_group_training_api_service.dart';
import 'package:ironbook_admin/services/admin_coaching_request_api_service.dart';
import 'package:ironbook_admin/services/admin_payment_api_service.dart';
import 'package:ironbook_admin/services/admin_reports_api_service.dart';
import 'package:ironbook_admin/widgets/admin_primitives.dart';

import 'support/token_provider.dart';
import 'support/paged_response.dart';
import 'admin_payments_test.dart' as payments;

http.Response json(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status);
Map<String, Object> center(int id) => {
  ...payments.center,
  'id': id,
  'name': 'Center $id',
};
Map<String, Object> trainer(int id, {bool active = true, int centerId = 3}) => {
  'id': id,
  'firstName': 'Trainer',
  'lastName': '$id',
  'email': '$id@example.invalid',
  'isActive': active,
  'createdAt': '2030-01-01T00:00:00Z',
  'centers': [
    {'centerId': centerId, 'centerName': 'Center', 'location': 'Test'},
  ],
};

void main() {
  test('one generic parser preserves metadata and empty items', () {
    final page = PagedResult.fromJson(
      pagedResponse([center(8)], page: 2, pageSize: 20, totalCount: 21),
      (item) => item['id'],
    );
    expect(page.items, [8]);
    expect(page.pageNumber, 2);
    expect(page.pageSize, 20);
    expect(page.totalCount, 21);
    expect(page.totalPages, 2);
    final empty = PagedResult.fromJson(pagedResponse([]), (item) => item);
    expect(empty.items, isEmpty);
    expect(empty.totalPages, 0);
  });

  test('malformed metadata/items use feature parsing errors', () async {
    for (final data in [
      [],
      {},
      {...pagedResponse([]), 'items': null},
      {...pagedResponse([]), 'pageNumber': '1'},
      {...pagedResponse([]), 'totalCount': -1},
    ]) {
      final api = AdminCenterApiService(
        accessTokenProvider: FakeAccessTokenProvider(),
        client: MockClient((_) async => json(data)),
      );
      await expectLater(
        api.getCenters(),
        throwsA(isA<AdminCenterApiException>()),
      );
    }
  });

  for (final feature in [
    'centers',
    'trainers',
    'plans',
    'groups',
    'coaching',
    'payments',
  ]) {
    test(
      '$feature management calls expose metadata, preserve filters and Bearer per page',
      () async {
        final seen = <http.Request>[];
        final tokens = FakeAccessTokenProvider();
        final client = MockClient((request) async {
          seen.add(request);
          expect(
            request.headers['Authorization'],
            'Bearer fixture-access-token',
          );
          expect(request.url.queryParameters['pageSize'], isNull);
          return json(
            pagedResponse(
              [],
              page: int.parse(request.url.queryParameters['pageNumber']!),
              totalCount: 40,
            ),
          );
        });
        addTearDown(client.close);
        Future<PagedResult<dynamic>> load(int page) => switch (feature) {
          'centers' => AdminCenterApiService(
            client: client,
            accessTokenProvider: tokens,
          ).getCenters(search: ' A & B ', pageNumber: page),
          'trainers' => AdminTrainerApiService(
            client: client,
            accessTokenProvider: tokens,
          ).getTrainers(search: ' A & B ', pageNumber: page),
          'plans' => AdminMembershipPlanApiService(
            client: client,
            accessTokenProvider: tokens,
          ).getMembershipPlans(search: ' A & B ', pageNumber: page),
          'groups' => AdminGroupTrainingApiService(
            client: client,
            accessTokenProvider: tokens,
          ).getGroupTrainings(search: ' A & B ', centerId: 3, pageNumber: page),
          'coaching' =>
            AdminCoachingRequestApiService(
              client: client,
              accessTokenProvider: tokens,
            ).getCoachingRequests(
              search: ' A & B ',
              status: 'Approved',
              pageNumber: page,
            ),
          _ =>
            AdminPaymentApiService(
              client: client,
              accessTokenProvider: tokens,
            ).getPayments(
              const AdminPaymentFilter(
                search: ' A & B ',
                status: 'Completed',
                centerId: 3,
                paymentMethod: 'Reception',
              ),
              pageNumber: page,
            ),
        };
        expect((await load(1)).pageNumber, 1);
        expect((await load(2)).pageNumber, 2);
        expect(
          seen.map((request) => request.url.queryParameters['search']),
          everyElement('A & B'),
        );
        final first = {...seen[0].url.queryParameters}..remove('pageNumber');
        final second = {...seen[1].url.queryParameters}..remove('pageNumber');
        expect(first, second);
      },
    );
  }

  for (final feature in ['payments', 'reports', 'forms']) {
    for (final fail in [false, true]) {
      test(
        '$feature center lookup loads all pages or fails without partial output ($fail)',
        () async {
          final seen = <int>[];
          final client = MockClient((request) async {
            final page = int.parse(request.url.queryParameters['pageNumber']!);
            seen.add(page);
            expect(request.url.queryParameters['pageSize'], '100');
            expect(
              request.headers['Authorization'],
              'Bearer fixture-access-token',
            );
            if (fail && page == 2) return json({'message': 'Offline'}, 500);
            return json(
              pagedResponse(
                [center(page)],
                page: page,
                pageSize: 100,
                totalCount: 101,
              ),
            );
          });
          addTearDown(client.close);
          final tokens = FakeAccessTokenProvider();
          final result = switch (feature) {
            'payments' => AdminPaymentApiService(
              client: client,
              accessTokenProvider: tokens,
            ).getCenters(),
            'reports' => AdminReportsApiService(
              client: client,
              accessTokenProvider: tokens,
            ).getFilterCenters(),
            _ => AdminCenterApiService(
              client: client,
              accessTokenProvider: tokens,
            ).getAllCenters(),
          };
          if (fail) {
            await expectLater(
              result,
              throwsA(
                predicate(
                  (error) => switch (feature) {
                    'payments' =>
                      error is AdminPaymentApiException &&
                          error.statusCode == 500,
                    'reports' =>
                      error is AdminReportsApiException &&
                          error.statusCode == 500,
                    _ =>
                      error is AdminCenterApiException &&
                          error.statusCode == 500,
                  },
                ),
              ),
            );
          } else {
            expect((await result).map((item) => item.id), [1, 2]);
          }
          expect(seen, [1, 2]);
        },
      );
    }
  }

  for (final fail in [false, true]) {
    test(
      'coaching lookup reads all pages then keeps active center trainers ($fail)',
      () async {
        final seen = <int>[];
        final api = AdminCoachingRequestApiService(
          accessTokenProvider: FakeAccessTokenProvider(),
          client: MockClient((request) async {
            final page = int.parse(request.url.queryParameters['pageNumber']!);
            seen.add(page);
            expect(request.url.queryParameters['pageSize'], '100');
            expect(
              request.headers['Authorization'],
              'Bearer fixture-access-token',
            );
            if (fail && page == 2) return json({}, 503);
            return json(
              pagedResponse(
                page == 1
                    ? [trainer(1), trainer(2, active: false)]
                    : [trainer(3), trainer(4, centerId: 9)],
                page: page,
                pageSize: 100,
                totalCount: 101,
              ),
            );
          }),
        );
        final result = api.getActiveTrainersForCenter(3);
        if (fail) {
          await expectLater(
            result,
            throwsA(isA<AdminCoachingRequestApiException>()),
          );
        } else {
          expect((await result).map((item) => item.id), [1, 3]);
        }
        expect(seen, [1, 2]);
      },
    );
  }

  test('mutation refresh falls back to last valid page', () async {
    final calls = <int>[];
    final result = await loadAvailablePage<int>(3, (number) async {
      calls.add(number);
      return PagedResult(
        items: number == 2 ? [21] : [],
        pageNumber: number,
        pageSize: 20,
        totalCount: 21,
        totalPages: 2,
      );
    });
    expect(calls, [3, 2]);
    expect(result.items, [21]);
  });

  testWidgets(
    'Centers Next/Previous/filter reset and page-two edit preserve IDs and page',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final seen = <http.Request>[];
      final api = AdminCenterApiService(
        accessTokenProvider: FakeAccessTokenProvider(),
        client: MockClient((request) async {
          seen.add(request);
          if (request.url.path.endsWith('/22')) return json(center(22));
          final page = int.parse(request.url.queryParameters['pageNumber']!);
          return json(
            pagedResponse(
              [center(page == 1 ? 11 : 22)],
              page: page,
              totalCount: 21,
            ),
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CentersManagementScreen(centerApiService: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(seen.first.url.queryParameters, {'pageNumber': '1'});
      expect(
        tester
            .widget<AdminButton>(find.widgetWithText(AdminButton, 'Previous'))
            .onPressed,
        isNull,
      );
      Future<void> tap(String text) async {
        await tester.ensureVisible(find.widgetWithText(AdminButton, text));
        await tester.tap(find.widgetWithText(AdminButton, text));
        await tester.pumpAndSettle();
      }

      await tap('Next');
      expect(find.text('Center 22'), findsOneWidget);
      expect(find.text('Center 11'), findsNothing);
      expect(
        tester
            .widget<AdminButton>(find.widgetWithText(AdminButton, 'Next'))
            .onPressed,
        isNull,
      );
      await tap('Edit');
      expect(seen.last.url.path, '/api/admin/centers/22');
      await tap('Save Center');
      expect(
        seen.any(
          (request) =>
              request.method == 'PUT' && request.url.path.endsWith('/22'),
        ),
        isTrue,
      );
      expect(seen.last.url.queryParameters['pageNumber'], '2');
      await tap('Previous');
      expect(find.text('Center 11'), findsOneWidget);
      await tap('Next');
      await tester.enterText(find.byType(TextField).first, 'New search');
      await tap('Search');
      expect(seen.last.url.queryParameters, {
        'pageNumber': '1',
        'search': 'New search',
      });
      await tap('Next');
      expect(seen.last.url.queryParameters, {
        'pageNumber': '2',
        'search': 'New search',
      });
    },
  );

  testWidgets('Payments page-two confirmation refreshes same filtered page', (
    tester,
  ) async {
    final seen = <http.Request>[];
    var completed = false;
    await payments.showPayments(
      tester,
      MockClient((request) async {
        seen.add(request);
        if (request.method == 'POST') {
          completed = true;
          return json(payments.payment(id: 22, completed: true));
        }
        if (request.url.path.endsWith('/centers')) {
          return json(pagedResponse([center(3)], pageSize: 100));
        }
        final page = int.parse(request.url.queryParameters['pageNumber']!);
        return json(
          pagedResponse(
            [payments.payment(id: page == 1 ? 11 : 22, completed: completed)],
            page: page,
            totalCount: 21,
          ),
        );
      }),
    );
    await tester.pumpAndSettle();
    await payments.tap(tester, find.text('Next'));
    await payments.tap(tester, find.byKey(const Key('confirm-payment-22')));
    await payments.tap(tester, find.text('Confirm Payment').last);
    expect(
      seen.any(
        (request) =>
            request.method == 'POST' &&
            request.url.path == '/api/admin/payments/22/confirm-reception',
      ),
      isTrue,
    );
    expect(
      seen
          .lastWhere((request) => request.url.path == '/api/admin/payments')
          .url
          .queryParameters['pageNumber'],
      '2',
    );
    expect(
      find.text('Payment confirmed. Membership activated.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Plans and Groups retain independent page controls on existing shared screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final seen = <http.Request>[];
      final tokens = FakeAccessTokenProvider();
      final client = MockClient((request) async {
        seen.add(request);
        final page = int.parse(request.url.queryParameters['pageNumber']!);
        return json(pagedResponse([], page: page, totalCount: 21));
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MembershipPlansScreen(
              membershipPlanApiService: AdminMembershipPlanApiService(
                client: client,
                accessTokenProvider: tokens,
              ),
              groupTrainingApiService: AdminGroupTrainingApiService(
                client: client,
                accessTokenProvider: tokens,
              ),
              centerApiService: AdminCenterApiService(
                client: client,
                accessTokenProvider: tokens,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Next').last);
      await tester.tap(find.text('Next').last);
      await tester.pumpAndSettle();
      expect(seen.last.url.path, '/api/admin/group-trainings');
      expect(seen.last.url.queryParameters['pageNumber'], '2');
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(find.text('Page 2 of 2'), findsOneWidget);
    },
  );
}
