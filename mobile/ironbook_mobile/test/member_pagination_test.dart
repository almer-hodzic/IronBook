import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/models/paged_result.dart';
import 'package:ironbook_mobile/screens/group_trainings_screen.dart';
import 'package:ironbook_mobile/screens/member_notifications_screen.dart';
import 'package:ironbook_mobile/screens/member_progress_log_screen.dart';
import 'package:ironbook_mobile/screens/my_trainings_screen.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';
import 'package:ironbook_mobile/theme/ironbook_mobile_theme.dart';

import 'member_discovery_bearer_test.dart' show groupJson;
import 'member_notifications_test.dart' show notification;
import 'member_training_bearer_test.dart' show report;
import 'my_trainings_test.dart' show training, confirmCancel;
import 'support/paged_fixture.dart';
import 'support/token_provider.dart';

CenterApiService apiFor(Future<http.Response> Function(http.Request) handler) {
  final client = MockClient(handler);
  addTearDown(client.close);
  return CenterApiService(
    client: client,
    apiBaseUrl: 'http://localhost',
    accessTokenProvider: FakeAccessTokenProvider(),
  );
}

int pageOf(http.Request request) =>
    int.parse(request.url.queryParameters['pageNumber']!);
http.Response pageResponse(
  http.Request request,
  List<Object?> items, {
  int total = 21,
}) => http.Response(
  jsonEncode(paged(items, pageNumber: pageOf(request), totalCount: total)),
  200,
);

Future<void> showScreen(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(600, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(theme: IronBookMobileTheme.theme, home: screen),
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

bool disabled(WidgetTester tester, String label) =>
    tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label))
        .onPressed ==
    null;

void main() {
  test('one generic model parses items and all page metadata', () {
    final page = PagedResult.fromJson(
      paged(
        [
          {'id': 9},
        ],
        pageNumber: 2,
        pageSize: 20,
        totalCount: 21,
      ),
      (json) => json['id'] as int,
    );
    expect(page.items, [9]);
    expect(page.pageNumber, 2);
    expect(page.pageSize, 20);
    expect(page.totalCount, 21);
    expect(page.totalPages, 2);
  });

  test('empty page is safe with zero totals', () {
    final page = PagedResult.fromJson(paged([]), (json) => json);
    expect(page.items, isEmpty);
    expect(page.totalCount, 0);
    expect(page.totalPages, 0);
  });

  test('malformed envelopes, items and metadata are rejected', () {
    for (final value in [
      [],
      {},
      {...paged([]), 'items': null},
      {...paged([]), 'pageNumber': 0},
      {...paged([]), 'pageSize': '20'},
      {...paged([]), 'totalCount': -1},
      {...paged([]), 'totalPages': null},
      {
        ...paged([]),
        'items': [7],
      },
    ]) {
      expect(
        () => PagedResult.fromJson(value, (json) => json),
        throwsFormatException,
      );
    }
  });

  final calls =
      <String, Future<PagedResult<dynamic>> Function(CenterApiService)>{
        'my-trainings': (api) =>
            api.getMyTrainings(pageNumber: 2, status: 'Approved'),
        'progress-log': (api) => api.getMemberProgressLog(
          pageNumber: 2,
          fromDate: DateTime(2030, 1, 2),
          toDate: DateTime(2030, 2, 3),
        ),
        'notifications': (api) => api.getMemberNotifications(pageNumber: 2),
        'group-trainings': (api) => api.getGroupTrainingsForCenter(
          7,
          pageNumber: 2,
          search: ' strength & recovery ',
        ),
      };
  for (final entry in calls.entries) {
    test('${entry.key} page 2 retains filters, Bearer and metadata', () async {
      final api = apiFor((request) async {
        expect(request.headers['Authorization'], 'Bearer fixture-access-token');
        expect(request.body, isEmpty);
        expect(
          request.url.path,
          entry.key == 'group-trainings'
              ? '/api/centers/7/group-trainings'
              : '/api/member/${entry.key}',
        );
        expect(request.url.queryParameters, {
          'pageNumber': '2',
          'pageSize': '20',
          if (entry.key == 'my-trainings') 'status': 'Approved',
          if (entry.key == 'progress-log') ...{
            'fromDate': '2030-01-02',
            'toDate': '2030-02-03',
          },
          if (entry.key == 'group-trainings') 'search': 'strength & recovery',
        });
        return pageResponse(request, [
          switch (entry.key) {
            'my-trainings' => training(id: 8),
            'progress-log' => report,
            'notifications' => notification(id: 8),
            _ => groupJson,
          },
        ]);
      });
      final page = await entry.value(api);
      expect(page.pageNumber, 2);
      expect(page.totalCount, 21);
      expect(page.totalPages, 2);
      expect(page.items, hasLength(1));
    });
    test('${entry.key} malformed page uses CenterApiException', () async {
      final api = apiFor((_) async => http.Response('{"items": []}', 200));
      await expectLater(entry.value(api), throwsA(isA<CenterApiException>()));
    });
  }

  testWidgets('My Trainings replaces pages, Previous and filter reset work', (
    tester,
  ) async {
    final queries = <Map<String, String>>[];
    final api = apiFor((request) async {
      queries.add(request.url.queryParameters);
      return pageResponse(request, [training(id: pageOf(request))]);
    });
    await showScreen(tester, MyTrainingsScreen(centerApiService: api));
    expect(queries.single, {'pageNumber': '1', 'pageSize': '20'});
    expect(disabled(tester, 'Previous'), isTrue);
    await tap(tester, 'Next');
    expect(find.text('Trainer 2'), findsOneWidget);
    expect(find.text('Trainer 1'), findsNothing);
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(disabled(tester, 'Next'), isTrue);
    await tap(tester, 'Previous');
    expect(find.text('Trainer 1'), findsOneWidget);
    await tap(tester, 'Next');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Approved'));
    await tester.pumpAndSettle();
    expect(queries.last, {
      'pageNumber': '1',
      'pageSize': '20',
      'status': 'Approved',
    });
    await tap(tester, 'Next');
    expect(queries.last['status'], 'Approved');
  });

  for (final lastPageRemoved in [false, true]) {
    testWidgets(
      'cancellation refreshes page 2 with fallback=$lastPageRemoved',
      (tester) async {
        var cancelled = false;
        final pages = <int>[];
        final api = apiFor((request) async {
          if (request.method == 'POST') {
            expect(request.url.path, '/api/member/my-trainings/2/cancel');
            expect(jsonDecode(request.body), isEmpty);
            cancelled = true;
            return http.Response(
              jsonEncode(training(id: 2, status: 'Cancelled')),
              200,
            );
          }
          pages.add(pageOf(request));
          return pageResponse(
            request,
            cancelled && lastPageRemoved
                ? []
                : [
                    training(
                      id: pageOf(request),
                      status: cancelled ? 'Cancelled' : 'Pending',
                    ),
                  ],
            total: cancelled && lastPageRemoved ? 20 : 21,
          );
        });
        await showScreen(tester, MyTrainingsScreen(centerApiService: api));
        await tap(tester, 'Next');
        await confirmCancel(tester);
        expect(pages, lastPageRemoved ? [1, 2, 2, 1] : [1, 2, 2]);
        expect(
          find.text(lastPageRemoved ? 'Page 1 of 1' : 'Page 2 of 2'),
          findsOneWidget,
        );
        expect(find.text('Training cancelled.'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'Progress Log pages preserve exercises and dates reset to page 1',
    (tester) async {
      final queries = <Map<String, String>>[];
      final api = apiFor((request) async {
        queries.add(request.url.queryParameters);
        return pageResponse(request, [
          {...report, 'reportNotes': 'Page ${pageOf(request)} notes'},
        ]);
      });
      await showScreen(tester, MemberProgressLogScreen(centerApiService: api));
      expect(disabled(tester, 'Previous'), isTrue);
      await tap(tester, 'Next');
      expect(find.text('Page 1 notes'), findsNothing);
      expect(find.text('Page 2 notes'), findsOneWidget);
      expect(find.text('Squat'), findsOneWidget);
      expect(find.text('Stretch'), findsOneWidget);
      expect(disabled(tester, 'Next'), isTrue);
      await tap(tester, 'From: Any date');
      await tester.tap(find.text('10').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(queries.last['pageNumber'], '1');
      expect(queries.last['fromDate'], isNotEmpty);
      await tap(tester, 'Next');
      expect(queries.last['pageNumber'], '2');
      expect(queries.last['fromDate'], queries[2]['fromDate']);
      await tap(tester, 'Clear filters');
      expect(queries.last, {'pageNumber': '1', 'pageSize': '20'});
    },
  );

  testWidgets(
    'Notifications page 2 mark-read stays on page with the correct ID',
    (tester) async {
      final pages = <int>[];
      var puts = 0;
      final api = apiFor((request) async {
        if (request.method == 'PUT') {
          puts++;
          expect(request.url.path, '/api/member/notifications/2/read');
          expect(jsonDecode(request.body), isEmpty);
          return http.Response(
            jsonEncode(notification(id: 2, read: true)),
            200,
          );
        }
        pages.add(pageOf(request));
        return pageResponse(request, [notification(id: pageOf(request))]);
      });
      await showScreen(
        tester,
        MemberNotificationsScreen(centerApiService: api),
      );
      expect(disabled(tester, 'Previous'), isTrue);
      await tap(tester, 'Next');
      expect(find.text('Coaching request 1'), findsNothing);
      expect(find.text('Coaching request 2'), findsOneWidget);
      await tap(tester, 'Coaching request 2');
      expect(find.text('Read'), findsOneWidget);
      expect(find.text('0 unread on this page'), findsOneWidget);
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(disabled(tester, 'Next'), isTrue);
      expect(pages, [1, 2]);
      expect(puts, 1);
      await tap(tester, 'Previous');
      expect(pages, [1, 2, 1]);
    },
  );

  testWidgets('page failure retries the selected notification page', (
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
      return pageResponse(request, [notification(id: pageOf(request))]);
    });
    await showScreen(tester, MemberNotificationsScreen(centerApiService: api));
    await tap(tester, 'Next');
    expect(find.text('Notifications unavailable'), findsOneWidget);
    expect(find.text('Coaching request 1'), findsNothing);
    await tap(tester, 'Retry');
    expect(pages, [1, 2, 2]);
    expect(find.text('Page 2 of 2'), findsOneWidget);
  });

  testWidgets('Group pages preserve search and Center changes reset page 1', (
    tester,
  ) async {
    final requests = <Uri>[];
    final api = apiFor((request) async {
      requests.add(request.url);
      return pageResponse(request, [
        {...groupJson, 'name': 'Class ${pageOf(request)}'},
      ]);
    });
    Widget screen(int center) => GroupTrainingsScreen(
      centerId: center,
      centerName: 'Center $center',
      centerApiService: api,
    );
    await showScreen(tester, screen(7));
    expect(disabled(tester, 'Previous'), isTrue);
    await tap(tester, 'Next');
    expect(find.text('Class 1'), findsNothing);
    expect(find.text('Class 2'), findsOneWidget);
    expect(disabled(tester, 'Next'), isTrue);
    await tester.enterText(find.byType(TextField), ' strength ');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters, {
      'pageNumber': '1',
      'pageSize': '20',
      'search': 'strength',
    });
    await tap(tester, 'Next');
    expect(requests.last.queryParameters['search'], 'strength');
    await tester.pumpWidget(
      MaterialApp(theme: IronBookMobileTheme.theme, home: screen(8)),
    );
    await tester.pumpAndSettle();
    expect(requests.last.path, '/api/centers/8/group-trainings');
    expect(requests.last.queryParameters, {
      'pageNumber': '1',
      'pageSize': '20',
      'search': 'strength',
    });
    await tap(tester, 'Next');
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(requests.last.queryParameters, {
      'pageNumber': '1',
      'pageSize': '20',
    });
  });

  for (final lastPageRemoved in [false, true]) {
    testWidgets(
      'enrollment returns to current valid Group page with fallback=$lastPageRemoved',
      (tester) async {
        var enrolled = false;
        final pages = <int>[];
        final api = apiFor((request) async {
          final data = {
            ...groupJson,
            'isEnrolled': enrolled,
            'capacity': 10,
            'enrolledCount': enrolled ? 1 : 0,
            'availableSpots': enrolled ? 9 : 10,
          };
          if (request.method == 'POST') {
            expect(
              request.url.path,
              '/api/centers/7/group-trainings/22/enroll',
            );
            expect(jsonDecode(request.body), isEmpty);
            enrolled = true;
            return http.Response(
              jsonEncode({
                'id': 99,
                'groupTrainingId': 22,
                'memberProfileId': 4,
                'status': 'Active',
                'enrolledAt': '2030-01-01T10:00:00Z',
              }),
              201,
            );
          }
          if (request.url.path.endsWith('/22')) {
            return http.Response(jsonEncode(data), 200);
          }
          pages.add(pageOf(request));
          return pageResponse(
            request,
            enrolled && lastPageRemoved ? [] : [data],
            total: enrolled && lastPageRemoved ? 20 : 21,
          );
        });
        await showScreen(
          tester,
          GroupTrainingsScreen(
            centerId: 7,
            centerName: 'Selected center',
            centerApiService: api,
          ),
        );
        await tap(tester, 'Next');
        await tap(tester, 'View Details');
        await tap(tester, 'Join Training');
        expect(find.text('Enrollment confirmed.'), findsOneWidget);
        await tap(tester, 'Back');
        expect(pages, lastPageRemoved ? [1, 2, 2, 1] : [1, 2, 2]);
        expect(
          find.text(lastPageRemoved ? 'Page 1 of 1' : 'Page 2 of 2'),
          findsOneWidget,
        );
      },
    );
  }

  test('home unread count includes notifications on every page', () async {
    final pages = <int>[];
    final api = apiFor((request) async {
      expect(request.url.queryParameters['pageSize'], '100');
      pages.add(pageOf(request));
      return http.Response(
        jsonEncode(
          paged(
            [notification(id: pageOf(request), read: false)],
            pageNumber: pageOf(request),
            pageSize: 100,
            totalCount: 101,
          ),
        ),
        200,
      );
    });
    expect(await api.getUnreadNotificationCount(), 2);
    expect(pages, [1, 2]);
  });

  test(
    'home unread count never returns a partial count after later-page failure',
    () async {
      final api = apiFor(
        (request) async => pageOf(request) == 2
            ? http.Response('', 500)
            : http.Response(
                jsonEncode(
                  paged([notification()], pageSize: 100, totalCount: 101),
                ),
                200,
              ),
      );
      await expectLater(
        api.getUnreadNotificationCount(),
        throwsA(isA<CenterApiException>()),
      );
    },
  );
}
