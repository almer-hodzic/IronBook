import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/screens/trainer_dashboard_screen.dart';
import 'package:ironbook_mobile/screens/trainer_client_details_screen.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';
import 'package:ironbook_mobile/theme/ironbook_mobile_theme.dart';

import 'my_trainings_test.dart' show training;
import 'support/paged_fixture.dart';
import 'support/token_provider.dart';
import 'trainer_dashboard_bearer_test.dart' show requestJson;

CenterApiService apiFor(
  Future<http.Response> Function(http.Request) handler, {
  FakeAccessTokenProvider? tokens,
}) {
  final client = MockClient(handler);
  addTearDown(client.close);
  return CenterApiService(
    client: client,
    apiBaseUrl: 'http://localhost',
    accessTokenProvider: tokens ?? FakeAccessTokenProvider(),
  );
}

int pageOf(http.Request request) =>
    int.parse(request.url.queryParameters['pageNumber']!);
http.Response dashboardPage(http.Request request, {int total = 21}) {
  final number = pageOf(request);
  return http.Response(
    jsonEncode(
      paged(
        [
          for (
            var id = (number - 1) * 20 + 1;
            id <= number * 20 && id <= total;
            id++
          )
            {...requestJson, 'id': id, 'memberName': 'Member $id'},
        ],
        pageNumber: number,
        totalCount: total,
      ),
    ),
    200,
  );
}

Map<String, Object?> details({bool hasReport = false}) => {
  ...requestJson,
  'id': 21,
  'memberName': 'Member 21',
  'fitnessGoal': 'Build Strength',
  'note': 'Original notes',
  'hasTrainingReport': hasReport,
};

Future<void> showDashboard(WidgetTester tester, CenterApiService api) async {
  await tester.binding.setSurfaceSize(const Size(600, 1500));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: IronBookMobileTheme.theme,
      home: TrainerDashboardScreen(centerApiService: api),
    ),
  );
}

Future<void> tap(WidgetTester tester, String label) async {
  // A full page changes the lazy ListView's estimated scroll extent.
  final target = find.text(label).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

bool disabled(WidgetTester tester, String label) =>
    tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label))
        .onPressed ==
    null;

void main() {
  test('Dashboard parses shared metadata and preserves server order with explicit paging', () async {
    final api = apiFor((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/trainer/dashboard/coaching-requests');
      expect(request.url.queryParameters, {'pageNumber': '3', 'pageSize': '5'});
      expect(request.body, isEmpty);
      expect(request.headers['Authorization'], 'Bearer fixture-access-token');
      return http.Response(
        jsonEncode(
          paged(
            [
              requestJson,
              {...requestJson, 'id': 3},
            ],
            pageNumber: 3,
            pageSize: 5,
            totalCount: 12,
          ),
        ),
        200,
      );
    });
    final result = await api.getTrainerDashboardRequests(
      pageNumber: 3,
      pageSize: 5,
    );
    expect(result.pageNumber, 3);
    expect(result.pageSize, 5);
    expect(result.totalCount, 12);
    expect(result.totalPages, 3);
    expect(result.items.map((row) => row.id), [8, 3]);
    expect(result.items.first.memberName, 'Member One');
    expect(result.items.first.status, 'Approved');
  });

  test('Dashboard empty page preserves zero totals', () async {
    final api = apiFor((_) async => http.Response(jsonEncode(paged([])), 200));
    final page = await api.getTrainerDashboardRequests();
    expect(page.items, isEmpty);
    expect(page.totalCount, 0);
    expect(page.totalPages, 0);
  });

  for (final payload in [
    [],
    {'items': []},
    paged([{}]),
  ]) {
    test(
      'malformed Dashboard payload uses CenterApiException: $payload',
      () async {
        final api = apiFor(
          (_) async => http.Response(jsonEncode(payload), 200),
        );
        await expectLater(
          api.getTrainerDashboardRequests(),
          throwsA(isA<CenterApiException>()),
        );
      },
    );
  }

  test(
    'later Dashboard page rejects missing/malformed token before network',
    () async {
      for (final token in [null, '', 'Bearer malformed']) {
        var calls = 0;
        final api = apiFor((_) async {
          calls++;
          return http.Response('', 500);
        }, tokens: FakeAccessTokenProvider(token));
        await expectLater(
          api.getTrainerDashboardRequests(pageNumber: 2),
          throwsA(
            isA<CenterApiException>().having(
              (error) => error.statusCode,
              'status',
              401,
            ),
          ),
        );
        expect(calls, 0);
      }
    },
  );

  for (final status in [401, 403]) {
    test(
      'page 2 keeps $status visible without retry or local-session change',
      () async {
        var calls = 0;
        final tokens = FakeAccessTokenProvider();
        final api = apiFor((request) async {
          calls++;
          expect(pageOf(request), 2);
          expect(
            request.headers['Authorization'],
            'Bearer fixture-access-token',
          );
          return http.Response('Private server detail', status);
        }, tokens: tokens);
        await expectLater(
          api.getTrainerDashboardRequests(pageNumber: 2),
          throwsA(
            isA<CenterApiException>()
                .having((error) => error.statusCode, 'status', status)
                .having(
                  (error) => error.toString(),
                  'safe error',
                  isNot(contains('Private server detail')),
                ),
          ),
        );
        expect(calls, 1);
        expect(tokens.reads, 1);
        expect(tokens.token, 'fixture-access-token');
      },
    );
  }

  testWidgets(
    'Dashboard starts page 1 size 20; Next/Previous replace rows and respect boundaries',
    (tester) async {
      final queries = <Map<String, String>>[];
      final api = apiFor((request) async {
        queries.add(request.url.queryParameters);
        expect(request.headers['Authorization'], 'Bearer fixture-access-token');
        return dashboardPage(request);
      });
      await showDashboard(tester, api);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(queries.single, {'pageNumber': '1', 'pageSize': '20'});
      expect(find.text('21 approved requests'), findsOneWidget);
      expect(find.text('Member 1'), findsOneWidget);
      expect(disabled(tester, 'Previous'), isTrue);
      await tap(tester, 'Next');
      expect(queries.last, {'pageNumber': '2', 'pageSize': '20'});
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(find.text('Member 1'), findsNothing);
      expect(find.text('Member 21'), findsOneWidget);
      expect(find.text('21 approved requests'), findsOneWidget);
      expect(disabled(tester, 'Next'), isTrue);
      await tap(tester, 'Previous');
      expect(queries.last['pageNumber'], '1');
      expect(find.text('Member 21'), findsNothing);
      expect(find.text('Member 1'), findsOneWidget);
    },
  );

  testWidgets(
    'Dashboard retains loading/error/retry/empty states and empty boundaries',
    (tester) async {
      final response = Completer<http.Response>();
      var gets = 0;
      final api = apiFor(
        (_) async => ++gets == 1
            ? response.future
            : http.Response(jsonEncode(paged([])), 200),
      );
      await showDashboard(tester, api);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      response.complete(http.Response('', 500));
      await tester.pumpAndSettle();
      expect(find.text('Requests unavailable'), findsOneWidget);
      await tap(tester, 'Retry');
      expect(find.text('No approved requests'), findsOneWidget);
      expect(find.text('Page 1 of 1'), findsOneWidget);
      expect(disabled(tester, 'Previous'), isTrue);
      expect(disabled(tester, 'Next'), isTrue);
      expect(gets, 2);
    },
  );

  testWidgets('later-page error retries page 2 without displaying old rows', (
    tester,
  ) async {
    var failed = false;
    final pages = <int>[];
    final api = apiFor((request) async {
      pages.add(pageOf(request));
      if (pageOf(request) == 2 && !failed) {
        failed = true;
        return http.Response('', 500);
      }
      return dashboardPage(request);
    });
    await showDashboard(tester, api);
    await tester.pumpAndSettle();
    await tap(tester, 'Next');
    expect(find.text('Requests unavailable'), findsOneWidget);
    expect(find.text('Member 1'), findsNothing);
    await tap(tester, 'Retry');
    expect(pages, [1, 2, 2]);
    expect(find.text('Page 2 of 2'), findsOneWidget);
  });

  for (final removedPage in [false, true]) {
    testWidgets(
      'page 2 opens correct unpaged Details and refreshes with fallback=$removedPage',
      (tester) async {
        var visited = false;
        final pages = <int>[];
        var detailsCalls = 0;
        final api = apiFor((request) async {
          if (request.url.path.endsWith('/21')) {
            detailsCalls++;
            expect(request.url.queryParameters, isEmpty);
            expect(
              request.headers['Authorization'],
              'Bearer fixture-access-token',
            );
            visited = true;
            return http.Response(jsonEncode(details(hasReport: true)), 200);
          }
          pages.add(pageOf(request));
          return dashboardPage(
            request,
            total: visited && removedPage ? 20 : 21,
          );
        });
        await showDashboard(tester, api);
        await tester.pumpAndSettle();
        await tap(tester, 'Next');
        await tap(tester, 'Member 21');
        expect(find.byType(TrainerClientDetailsScreen), findsOneWidget);
        expect(find.text('Original notes'), findsOneWidget);
        expect(find.text('Add Training Report'), findsNothing);
        await tap(tester, 'Back');
        expect(pages, removedPage ? [1, 2, 2, 1] : [1, 2, 2]);
        expect(
          find.text(removedPage ? 'Page 1 of 1' : 'Page 2 of 2'),
          findsOneWidget,
        );
        expect(detailsCalls, 1);
      },
    );
  }

  testWidgets(
    'saved report is reflected when reopening Details without losing Dashboard page 2',
    (tester) async {
      var hasReport = false;
      var posts = 0;
      var detailsCalls = 0;
      final pages = <int>[];
      final api = apiFor((request) async {
        expect(request.headers['Authorization'], 'Bearer fixture-access-token');
        if (request.method == 'POST') {
          expect(request.url.path, '/api/trainer/training-reports');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(
            body.keys,
            unorderedEquals([
              'trainingRequestId',
              'trainingDate',
              'notes',
              'exercises',
            ]),
          );
          expect(body['trainingRequestId'], 21);
          expect((body['trainingDate'] as String).endsWith('Z'), isTrue);
          final exercise =
              (body['exercises'] as List).single as Map<String, dynamic>;
          expect(exercise, {
            'exerciseName': 'Squat',
            'sets': 3,
            'reps': 10,
            'weight': null,
            'notes': null,
          });
          posts++;
          hasReport = true;
          return http.Response(
            jsonEncode({
              'id': 19,
              'trainingRequestId': 21,
              'trainerProfileId': 3,
              'memberProfileId': 4,
              'centerId': 7,
              'trainingDate': body['trainingDate'],
              'notes': body['notes'],
              'createdAt': '2030-01-16T09:00:00Z',
              'exercises': [
                {...exercise, 'id': 20},
              ],
            }),
            201,
          );
        }
        if (request.url.path.endsWith('/21')) {
          detailsCalls++;
          expect(request.url.queryParameters, isEmpty);
          return http.Response(jsonEncode(details(hasReport: hasReport)), 200);
        }
        pages.add(pageOf(request));
        return dashboardPage(request);
      });
      await showDashboard(tester, api);
      await tester.pumpAndSettle();
      await tap(tester, 'Next');
      await tap(tester, 'Member 21');
      expect(find.text('Add Training Report'), findsOneWidget);
      // Exercise the unchanged API; Client Details' existing report-button
      // navigation is outside this pagination change.
      final saved = await api.createTrainingReport(
        trainingRequestId: 21,
        trainingDate: DateTime.utc(2030, 1, 15, 10),
        exercises: [
          {
            'exerciseName': 'Squat',
            'sets': 3,
            'reps': 10,
            'weight': null,
            'notes': null,
          },
        ],
      );
      expect(saved.trainingRequestId, 21);
      expect(posts, 1);
      expect(detailsCalls, 1);
      await tap(tester, 'Back');
      expect(pages, [1, 2, 2]);
      expect(find.text('Page 2 of 2'), findsOneWidget);
      await tap(tester, 'Member 21');
      expect(detailsCalls, 2);
      expect(find.text('Add Training Report'), findsNothing);
    },
  );

  test(
    'representative Member paged request keeps its contract and Bearer',
    () async {
      final api = apiFor((request) async {
        expect(request.url.path, '/api/member/my-trainings');
        expect(request.url.queryParameters, {
          'pageNumber': '2',
          'pageSize': '20',
          'status': 'Approved',
        });
        expect(request.headers['Authorization'], 'Bearer fixture-access-token');
        return http.Response(
          jsonEncode(
            paged(
              [training(status: 'Approved')],
              pageNumber: 2,
              totalCount: 21,
            ),
          ),
          200,
        );
      });
      final page = await api.getMyTrainings(pageNumber: 2, status: 'Approved');
      expect(page.pageNumber, 2);
      expect(page.totalCount, 21);
      expect(page.items.single.status, 'Approved');
    },
  );
}
