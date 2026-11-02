import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_auth/ironbook_auth.dart';
import 'package:ironbook_mobile/main.dart';
import 'package:ironbook_mobile/models/center.dart';
import 'package:ironbook_mobile/models/member_notification.dart';
import 'package:ironbook_mobile/models/paged_result.dart';
import 'package:ironbook_mobile/screens/center_list_screen.dart';
import 'package:ironbook_mobile/screens/member_notifications_screen.dart';
import 'package:ironbook_mobile/screens/recommendations_screen.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';
import 'package:ironbook_mobile/services/member_notification_poller.dart';
import 'package:ironbook_mobile/theme/ironbook_mobile_theme.dart';

import 'member_notifications_test.dart' show notification;
import 'recommendations_test.dart' show responseData;
import 'support/auth_fixture.dart';
import 'support/paged_fixture.dart';
import 'support/token_provider.dart';

const inbox = '/api/member/notifications';

class Fixture {
  final requests = <http.Request>[];
  final tokens = FakeAccessTokenProvider();
  List<Object?> items = [notification()];
  Future<http.Response> Function(http.Request)? respond;
  late final client = MockClient((request) async {
    requests.add(request);
    if (respond != null) return respond!(request);
    if (request.url.path == '/api/centers') return http.Response('[]', 200);
    return jsonPage(request, items);
  });
  late final api = CenterApiService(
    client: client,
    apiBaseUrl: 'http://localhost',
    accessTokenProvider: tokens,
  );

  List<http.Request> get counts => requests
      .where(
        (request) =>
            request.url.path == inbox &&
            request.url.queryParameters['pageSize'] == '100',
      )
      .toList();
  List<http.Request> get pages => requests
      .where(
        (request) =>
            request.url.path == inbox &&
            request.url.queryParameters['pageSize'] == '20',
      )
      .toList();
}

http.Response jsonPage(
  http.Request request,
  List<Object?> items, {
  int? total,
}) => http.Response(
  jsonEncode(
    paged(
      items,
      pageNumber: int.parse(request.url.queryParameters['pageNumber']!),
      pageSize: int.parse(request.url.queryParameters['pageSize']!),
      totalCount: total,
    ),
  ),
  200,
);

// Controlled, timeout-free transport for testing a refresh lasting multiple fake intervals.
class ControlledApi extends CenterApiService {
  final pages = <int>[];
  int active = 0;
  int maxActive = 0;
  Future<PagedResult<MemberNotification>> Function(int, int)? respond;
  @override
  Future<List<FitnessCenter>> getCenters() async => [];
  @override
  Future<PagedResult<MemberNotification>> getMemberNotifications({
    int pageNumber = 1,
    int pageSize = 20,
  }) async {
    pages.add(pageNumber);
    active++;
    if (active > maxActive) maxActive = active;
    try {
      return await (respond?.call(pageNumber, pageSize) ??
          Future.value(modelPage(pageNumber, pageSize)));
    } finally {
      active--;
    }
  }
}

PagedResult<MemberNotification> modelPage(
  int number,
  int size, {
  int id = 1,
  int total = 1,
}) => PagedResult.fromJson(
  paged(
    [notification(id: id)],
    pageNumber: number,
    pageSize: size,
    totalCount: total,
  ),
  MemberNotification.fromJson,
);

Future<void> show(
  WidgetTester tester,
  Widget screen, {
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(
    () => tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    ),
  );
  await tester.pumpWidget(
    MaterialApp(theme: IronBookMobileTheme.theme, home: screen),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> tick(
  WidgetTester tester, [
  Duration duration = MemberNotificationPoller.interval,
]) async {
  await tester.pump(duration);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).first);
  await tester.tap(find.text(text).first);
  await tester.pumpAndSettle();
}

Badge badge(WidgetTester tester) =>
    tester.widget<Badge>(find.byType(Badge, skipOffstage: false));
String badgeText(WidgetTester tester) => (badge(tester).label! as Text).data!;

void pauseApp(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void resumeApp(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void main() {
  late Fixture fixture;
  setUp(() => fixture = Fixture());
  tearDown(() => fixture.client.close());

  testWidgets(
    'home refreshes after 30 seconds without fetching unrelated Center data',
    (tester) async {
      await show(tester, CenterListScreen(centerApiService: fixture.api));
      expect(badgeText(tester), '1');
      fixture.items = [notification(), notification(id: 2)];
      await tick(tester, const Duration(seconds: 29));
      expect(fixture.counts.length, 1);
      await tick(tester, const Duration(seconds: 1));
      expect(badgeText(tester), '2');
      expect(fixture.counts.length, 2);
      expect(
        fixture.requests
            .where((request) => request.url.path == '/api/centers')
            .length,
        1,
      );
    },
  );

  testWidgets(
    'automatic badge refresh counts every page with no Center filter',
    (tester) async {
      var read = false;
      fixture.respond = (request) async {
        if (request.url.path == '/api/centers') return http.Response('[]', 200);
        final number = int.parse(request.url.queryParameters['pageNumber']!);
        expect(request.url.queryParameters.keys.toSet(), {
          'pageNumber',
          'pageSize',
        });
        return jsonPage(request, [
          notification(id: number, read: read && number == 2),
        ], total: 101);
      };
      await show(tester, CenterListScreen(centerApiService: fixture.api));
      expect(badgeText(tester), '2');
      read = true;
      await tick(tester);
      expect(badgeText(tester), '1');
      expect(
        fixture.counts.map(
          (request) => request.url.queryParameters['pageNumber'],
        ),
        ['1', '2', '1', '2'],
      );
    },
  );

  testWidgets(
    'later-page poll failure retains last complete count and never spams errors',
    (tester) async {
      var fail = false;
      fixture.respond = (request) async {
        if (request.url.path == '/api/centers') return http.Response('[]', 200);
        final number = int.parse(request.url.queryParameters['pageNumber']!);
        if (fail && number == 2) return http.Response('', 500);
        return jsonPage(request, [notification(id: number)], total: 101);
      };
      await show(tester, CenterListScreen(centerApiService: fixture.api));
      fail = true;
      await tick(tester);
      await tick(tester);
      expect(badgeText(tester), '2');
      expect(badge(tester).isLabelVisible, isTrue);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('could not be loaded'), findsNothing);
    },
  );

  testWidgets(
    'initial later-page failure leaves badge unknown instead of showing partial count',
    (tester) async {
      fixture.respond = (request) async {
        if (request.url.path == '/api/centers') return http.Response('[]', 200);
        return request.url.queryParameters['pageNumber'] == '2'
            ? http.Response('', 500)
            : jsonPage(request, [notification()], total: 101);
      };
      await show(tester, CenterListScreen(centerApiService: fixture.api));
      expect(badge(tester).isLabelVisible, isFalse);
      expect(fixture.counts.length, 2);
    },
  );

  testWidgets(
    'screen polls replace rows without duplicates and retain backend ordering',
    (tester) async {
      await show(
        tester,
        MemberNotificationsScreen(centerApiService: fixture.api),
      );
      fixture.items = [notification(id: 3), notification(id: 2)];
      await tick(tester);
      expect(find.text('Coaching request 1'), findsNothing);
      expect(find.text('Coaching request 3'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Coaching request 3')).dy,
        lessThan(tester.getTopLeft(find.text('Coaching request 2')).dy),
      );
      await tick(tester);
      expect(find.text('Coaching request 3'), findsOneWidget);
      expect(find.text('Coaching request 2'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('poll preserves current page and confirmed read state', (
    tester,
  ) async {
    var read = false;
    fixture.respond = (request) async => jsonPage(request, [
      notification(
        id: int.parse(request.url.queryParameters['pageNumber']!),
        read: read,
      ),
    ], total: 21);
    await show(
      tester,
      MemberNotificationsScreen(centerApiService: fixture.api),
    );
    await tap(tester, 'Next');
    read = true;
    await tick(tester);
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(find.text('Coaching request 1'), findsNothing);
    expect(find.text('Coaching request 2'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(
      fixture.pages.map((request) => request.url.queryParameters['pageNumber']),
      ['1', '2', '2'],
    );
  });

  testWidgets(
    'poll uses existing last-page fallback when current page disappears',
    (tester) async {
      var removed = false;
      fixture.respond = (request) async {
        final number = int.parse(request.url.queryParameters['pageNumber']!);
        return jsonPage(
          request,
          removed && number == 2
              ? []
              : [notification(id: removed ? 9 : number)],
          total: removed ? 1 : 21,
        );
      };
      await show(
        tester,
        MemberNotificationsScreen(centerApiService: fixture.api),
      );
      await tap(tester, 'Next');
      removed = true;
      await tick(tester);
      expect(find.text('Page 1 of 1'), findsOneWidget);
      expect(find.text('Coaching request 9'), findsOneWidget);
      expect(find.text('Coaching request 2'), findsNothing);
      expect(
        fixture.pages.map(
          (request) => request.url.queryParameters['pageNumber'],
        ),
        ['1', '2', '2', '1'],
      );
    },
  );

  testWidgets('manual refresh uses current page just like polling', (
    tester,
  ) async {
    fixture.respond = (request) async => jsonPage(request, [
      notification(id: int.parse(request.url.queryParameters['pageNumber']!)),
    ], total: 21);
    await show(
      tester,
      MemberNotificationsScreen(centerApiService: fixture.api),
    );
    await tap(tester, 'Next');
    await tap(tester, 'Refresh');
    await tick(tester);
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(
      fixture.pages.map((request) => request.url.queryParameters['pageNumber']),
      ['1', '2', '2', '2'],
    );
  });

  testWidgets('mark read refreshes complete home badge before returning', (
    tester,
  ) async {
    var read = false;
    fixture.respond = (request) async {
      if (request.url.path == '/api/centers') return http.Response('[]', 200);
      if (request.method == 'PUT') {
        expect(request.url.path, '$inbox/1/read');
        expect(jsonDecode(request.body), isEmpty);
        read = true;
        return http.Response(jsonEncode(notification(read: true)), 200);
      }
      return jsonPage(request, [notification(read: read)]);
    };
    await show(tester, CenterListScreen(centerApiService: fixture.api));
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    await tap(tester, 'Coaching request 1');
    expect(find.text('Read'), findsOneWidget);
    expect(badge(tester).isLabelVisible, isFalse);
    expect(fixture.counts.length, 2);
    expect(find.byType(MemberNotificationsScreen), findsOneWidget);
  });

  testWidgets('failed mark read preserves unread row and badge', (
    tester,
  ) async {
    fixture.respond = (request) async {
      if (request.url.path == '/api/centers') return http.Response('[]', 200);
      if (request.method == 'PUT') return http.Response('', 500);
      return jsonPage(request, [notification()]);
    };
    await show(tester, CenterListScreen(centerApiService: fixture.api));
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    await tap(tester, 'Coaching request 1');
    expect(find.text('Unread'), findsOneWidget);
    expect(find.textContaining('could not be marked as read'), findsOneWidget);
    expect(badgeText(tester), '1');
    expect(fixture.counts.length, 1);
  });

  testWidgets(
    'mark read coalesces a fresh count after an older count without overlap',
    (tester) async {
      var read = false;
      var activeCounts = 0;
      var maxActiveCounts = 0;
      final pending = Completer<http.Response>();
      fixture.respond = (request) async {
        if (request.url.path == '/api/centers') return http.Response('[]', 200);
        if (request.method == 'PUT') {
          read = true;
          return http.Response(jsonEncode(notification(read: true)), 200);
        }
        if (request.url.queryParameters['pageSize'] == '100') {
          activeCounts++;
          if (activeCounts > maxActiveCounts) maxActiveCounts = activeCounts;
          try {
            if (fixture.counts.length == 1) return await pending.future;
            return jsonPage(request, [notification(read: read)]);
          } finally {
            activeCounts--;
          }
        }
        return jsonPage(request, [notification(read: read)]);
      };
      await show(tester, CenterListScreen(centerApiService: fixture.api));
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      await tap(tester, 'Coaching request 1');
      expect(find.text('Read'), findsOneWidget);
      expect(fixture.counts.length, 1);
      pending.complete(jsonPage(fixture.counts.first, [notification()]));
      await tester.pumpAndSettle();
      expect(fixture.counts.length, 2);
      expect(badge(tester).isLabelVisible, isFalse);
      expect(maxActiveCounts, 1);
    },
  );

  testWidgets(
    'poll failures preserve visible rows silently; manual retry still reports errors',
    (tester) async {
      var fail = false;
      fixture.respond = (request) async =>
          fail ? http.Response('', 500) : jsonPage(request, [notification()]);
      await show(
        tester,
        MemberNotificationsScreen(centerApiService: fixture.api),
      );
      fail = true;
      await tick(tester);
      await tick(tester);
      expect(find.text('Coaching request 1'), findsOneWidget);
      expect(find.text('Notifications unavailable'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await tap(tester, 'Refresh');
      expect(find.text('Notifications unavailable'), findsOneWidget);
      fail = false;
      await tap(tester, 'Retry');
      expect(find.text('Coaching request 1'), findsOneWidget);
    },
  );

  testWidgets(
    'slow page refresh skips later polls and keeps current rows visible',
    (tester) async {
      final api = ControlledApi();
      final pending = Completer<PagedResult<MemberNotification>>();
      api.respond = (number, size) => api.pages.length == 2
          ? pending.future
          : Future.value(modelPage(number, size));
      await show(tester, MemberNotificationsScreen(centerApiService: api));
      await tick(tester);
      await tick(tester);
      await tick(tester);
      expect(api.pages, [1, 1]);
      expect(api.maxActive, 1);
      expect(find.text('Coaching request 1'), findsOneWidget);
      pending.complete(modelPage(1, 20, id: 2));
      await tester.pumpAndSettle();
      await tick(tester);
      expect(api.pages.length, 3);
      expect(api.maxActive, 1);
    },
  );

  testWidgets('slow all-pages badge count never overlaps with another count', (
    tester,
  ) async {
    final api = ControlledApi();
    final pending = Completer<PagedResult<MemberNotification>>();
    api.respond = (number, size) => api.pages.length == 2
        ? pending.future
        : Future.value(modelPage(number, size, id: number, total: 101));
    await show(tester, CenterListScreen(centerApiService: api));
    await tick(tester);
    await tick(tester);
    expect(api.pages, [1, 2]);
    expect(badge(tester).isLabelVisible, isFalse);
    pending.complete(modelPage(2, 100, id: 2, total: 101));
    await tester.pumpAndSettle();
    expect(badgeText(tester), '2');
    await tick(tester);
    expect(api.pages, [1, 2, 1, 2]);
    expect(api.maxActive, 1);
  });

  for (final home in [false, true]) {
    testWidgets(
      '${home ? 'home' : 'screen'} suspends all non-resumed states and immediately refreshes/restarts on resume',
      (tester) async {
        await show(
          tester,
          home
              ? CenterListScreen(centerApiService: fixture.api)
              : MemberNotificationsScreen(centerApiService: fixture.api),
        );
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.detached,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
          await tick(tester, const Duration(seconds: 60));
        }
        expect(home ? fixture.counts.length : fixture.pages.length, 1);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(home ? fixture.counts.length : fixture.pages.length, 2);
        await tick(tester, const Duration(seconds: 29));
        expect(home ? fixture.counts.length : fixture.pages.length, 2);
        await tick(tester, const Duration(seconds: 1));
        expect(home ? fixture.counts.length : fixture.pages.length, 3);
      },
    );
  }

  for (final home in [false, true]) {
    testWidgets(
      '${home ? 'home' : 'screen'} disposal stops timer and ignores late refresh completion',
      (tester) async {
        final api = ControlledApi();
        final pending = Completer<PagedResult<MemberNotification>>();
        api.respond = (number, size) => pending.future;
        await show(
          tester,
          home
              ? CenterListScreen(centerApiService: api)
              : MemberNotificationsScreen(centerApiService: api),
          settle: false,
        );
        await tester.pumpWidget(const SizedBox());
        pending.complete(modelPage(1, home ? 100 : 20));
        await tester.pumpAndSettle();
        await tick(tester, const Duration(seconds: 90));
        expect(api.pages, [1]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final disposed in [false, true]) {
    testWidgets(
      'a ${disposed ? 'disposed' : 'backgrounded'} badge stops before fetching another count page',
      (tester) async {
        final api = ControlledApi();
        final pending = Completer<PagedResult<MemberNotification>>();
        api.respond = (number, size) => api.pages.length == 1
            ? pending.future
            : Future.value(modelPage(number, size, id: number, total: 101));
        await show(tester, CenterListScreen(centerApiService: api));
        if (disposed) {
          await tester.pumpWidget(const SizedBox());
        } else {
          pauseApp(tester);
        }
        pending.complete(modelPage(1, 100, total: 101));
        await tester.pumpAndSettle();
        expect(api.pages, [1]);
        if (!disposed) {
          resumeApp(tester);
          await tester.pumpAndSettle();
          expect(api.pages, [1, 1, 2]);
          expect(badgeText(tester), '2');
        }
      },
    );
  }

  testWidgets(
    'resume during an in-flight page refresh coalesces one fresh request',
    (tester) async {
      final api = ControlledApi();
      final pending = Completer<PagedResult<MemberNotification>>();
      api.respond = (number, size) => api.pages.length == 2
          ? pending.future
          : Future.value(modelPage(number, size));
      await show(tester, MemberNotificationsScreen(centerApiService: api));
      await tick(tester);
      pauseApp(tester);
      resumeApp(tester);
      await tester.pump();
      expect(api.pages.length, 2);
      pending.complete(modelPage(1, 20));
      await tester.pumpAndSettle();
      expect(api.pages.length, 3);
      expect(api.maxActive, 1);
    },
  );

  testWidgets(
    'shared timer switches back to home and does not issue two page-count refreshes',
    (tester) async {
      await show(tester, CenterListScreen(centerApiService: fixture.api));
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      await tick(tester);
      expect(fixture.pages.length, 2); // Initial page and one poll.
      expect(
        fixture.counts.length,
        2,
      ); // Initial badge and the page poll's badge refresh.
      await tap(tester, 'Back');
      expect(fixture.counts.length, 3);
      await tick(tester);
      expect(fixture.counts.length, 4);
      expect(fixture.pages.length, 2);
    },
  );

  testWidgets(
    'each automatic request keeps current Bearer and unchanged pagination parameters',
    (tester) async {
      await show(
        tester,
        MemberNotificationsScreen(centerApiService: fixture.api),
      );
      fixture.tokens.token = 'changed-session-token';
      await tick(tester);
      expect(
        fixture.pages.first.headers['Authorization'],
        'Bearer fixture-access-token',
      );
      expect(
        fixture.pages.last.headers['Authorization'],
        'Bearer changed-session-token',
      );
      expect(fixture.pages.last.url.queryParameters, {
        'pageNumber': '1',
        'pageSize': '20',
      });
      expect(fixture.pages.last.body, isEmpty);
      expect(fixture.tokens.reads, 2);
    },
  );

  for (final openInbox in [false, true]) {
    testWidgets(
      'authenticated Member logout stops ${openInbox ? 'borrowed inbox' : 'home'} polling',
      (tester) async {
        final auth = AuthFixture()..persist();
        final controller = AuthController(auth.api);
        addTearDown(controller.dispose);
        addTearDown(auth.api.dispose);
        await show(
          tester,
          AuthGate(
            controller: controller,
            appTitle: 'Test',
            authenticatedRoots: {
              AuthRoles.member: (_) =>
                  CenterListScreen(centerApiService: fixture.api),
            },
          ),
        );
        if (openInbox) {
          await tester.tap(find.byTooltip('Notifications'));
          await tester.pumpAndSettle();
        }
        await controller.logout();
        await tester.pumpAndSettle();
        final before = fixture.requests.length;
        await tick(tester, const Duration(seconds: 90));
        expect(fixture.requests.length, before);
        expect(
          find.byType(CenterListScreen, skipOffstage: false),
          findsNothing,
        );
      },
    );
  }

  testWidgets(
    'unauthenticated and Trainer roots never start Member notification polling',
    (tester) async {
      final auth = AuthFixture();
      addTearDown(auth.api.dispose);
      await show(
        tester,
        IronBookMobileApp(
          authApiService: auth.api,
          centerApiService: fixture.api,
        ),
      );
      await tick(tester, const Duration(seconds: 60));
      expect(fixture.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
      auth.persist(role: AuthRoles.trainer);
      fixture.respond = (request) async =>
          http.Response(jsonEncode(paged([])), 200);
      await tester.pumpWidget(
        IronBookMobileApp(
          authApiService: auth.api,
          centerApiService: fixture.api,
        ),
      );
      await tester.pumpAndSettle();
      final before = fixture.requests.length;
      await tick(tester, const Duration(seconds: 60));
      expect(fixture.requests.length, before);
      expect(fixture.counts, isEmpty);
      expect(fixture.pages, isEmpty);
    },
  );

  testWidgets(
    'Recommendations keep their existing request and do not start a notification timer',
    (tester) async {
      fixture.respond = (request) async =>
          http.Response(jsonEncode(responseData()), 200);
      await show(
        tester,
        RecommendationsScreen(
          centerId: 7,
          centerName: 'Selected center',
          centerApiService: fixture.api,
        ),
      );
      expect(find.text('Trainer One'), findsWidgets);
      await tick(tester, const Duration(seconds: 60));
      expect(fixture.requests.length, 1);
      expect(
        fixture.requests.single.url.path,
        '/api/member/centers/7/recommendations',
      );
    },
  );
}
