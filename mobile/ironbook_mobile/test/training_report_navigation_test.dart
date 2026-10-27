import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/screens/add_training_report_screen.dart';
import 'package:ironbook_mobile/screens/trainer_client_details_screen.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';
import 'package:ironbook_mobile/theme/ironbook_mobile_theme.dart';

import 'support/token_provider.dart';
import 'trainer_dashboard_bearer_test.dart' show requestJson;

class ReportFixture {
  ReportFixture({this.hasReport = false});

  bool hasReport;
  int detailLoads = 0;
  int reportsSaved = 0;
  Map<String, dynamic>? savedBody;

  late final client = MockClient((request) async {
    expect(request.headers['Authorization'], 'Bearer fixture-access-token');
    expect(request.url.queryParameters, isEmpty);
    if (request.method == 'GET' &&
        request.url.path == '/api/trainer/dashboard/coaching-requests/8') {
      detailLoads++;
      return http.Response(
        jsonEncode({
          ...requestJson,
          'fitnessGoal': 'Build Strength',
          'note': 'Client notes',
          'hasTrainingReport': hasReport,
        }),
        200,
      );
    }
    if (request.method == 'POST' &&
        request.url.path == '/api/trainer/training-reports') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      savedBody = body;
      reportsSaved++;
      hasReport = true;
      return http.Response(
        jsonEncode({
          'id': 19,
          'trainingRequestId': body['trainingRequestId'],
          'trainerProfileId': 3,
          'memberProfileId': 4,
          'centerId': 7,
          'trainingDate': body['trainingDate'],
          'notes': body['notes'],
          'createdAt': '2030-01-16T09:00:00Z',
          'exercises': [
            for (final exercise in body['exercises'] as List)
              {...exercise as Map<String, dynamic>, 'id': 20},
          ],
        }),
        201,
      );
    }
    throw StateError(
      'Unexpected test request: ${request.method} ${request.url.path}',
    );
  });

  late final api = CenterApiService(
    client: client,
    apiBaseUrl: 'http://localhost',
    accessTokenProvider: FakeAccessTokenProvider(),
  );
}

class RouteObserverFixture extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    super.didPush(route, previousRoute);
  }
}

Future<void> showDetails(
  WidgetTester tester,
  ReportFixture fixture, {
  RouteObserverFixture? observer,
  GlobalKey<NavigatorState>? navigatorKey,
  bool launcher = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(fixture.client.close);
  Widget details() =>
      TrainerClientDetailsScreen(centerApiService: fixture.api, requestId: 8);
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [?observer],
      theme: IronBookMobileTheme.theme,
      home: launcher
          ? Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => details())),
                  child: const Text('Open client'),
                ),
              ),
            )
          : details(),
    ),
  );
  await tester.pumpAndSettle();
  if (launcher) await tap(tester, 'Open client');
}

Future<void> tap(WidgetTester tester, String label) async {
  final target = find.text(label).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

VoidCallback reportAction(WidgetTester tester) => tester
    .widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add Training Report'),
    )
    .onPressed!;

void main() {
  testWidgets(
    'Add Training Report opens the existing screen with the correct request and safely cancels',
    (tester) async {
      final fixture = ReportFixture();
      await showDetails(tester, fixture);
      expect(find.text('Member One'), findsOneWidget);
      expect(find.text('Client notes'), findsOneWidget);
      expect(find.text('Add Training Report'), findsOneWidget);
      await tap(tester, 'Add Training Report');
      expect(tester.takeException(), isNull);
      final report = tester.widget<AddTrainingReportScreen>(
        find.byType(AddTrainingReportScreen),
      );
      expect(report.trainingRequestId, 8);
      expect(report.centerApiService, same(fixture.api));
      expect(find.text('Exercise name'), findsOneWidget);
      await tap(tester, 'Back');
      expect(find.byType(AddTrainingReportScreen), findsNothing);
      expect(find.byType(TrainerClientDetailsScreen), findsOneWidget);
      expect(find.text('Add Training Report'), findsOneWidget);
      expect(fixture.detailLoads, 1);
      expect(fixture.reportsSaved, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rapid report actions create only one route and can reopen after cancellation',
    (tester) async {
      final fixture = ReportFixture();
      final observer = RouteObserverFixture();
      await showDetails(tester, fixture, observer: observer);
      final action = reportAction(tester);
      action();
      action();
      await tester.pumpAndSettle();
      expect(observer.pushed, hasLength(2));
      expect(find.byType(AddTrainingReportScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(tester, 'Back');
      await tap(tester, 'Add Training Report');
      expect(observer.pushed, hasLength(3));
      expect(find.byType(AddTrainingReportScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'successful form submission retains validation/payload and refreshes HasTrainingReport',
    (tester) async {
      final fixture = ReportFixture();
      await showDetails(tester, fixture);
      await tap(tester, 'Add Training Report');
      await tap(tester, 'Save report');
      expect(find.text('Enter an exercise name.'), findsOneWidget);
      expect(fixture.reportsSaved, 0);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Exercise name'),
        'Squat',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Session notes'),
        ' Session notes ',
      );
      await tap(tester, 'Save report');
      expect(tester.takeException(), isNull);
      expect(find.byType(AddTrainingReportScreen), findsNothing);
      expect(find.byType(TrainerClientDetailsScreen), findsOneWidget);
      expect(fixture.reportsSaved, 1);
      expect(fixture.detailLoads, 2);
      expect(find.text('Add Training Report'), findsNothing);
      expect(find.text('Member One'), findsOneWidget);
      expect(find.text('Client notes'), findsOneWidget);
      final body = fixture.savedBody!;
      expect(
        body.keys,
        unorderedEquals([
          'trainingRequestId',
          'trainingDate',
          'notes',
          'exercises',
        ]),
      );
      expect(body['trainingRequestId'], 8);
      expect((body['trainingDate'] as String).endsWith('Z'), isTrue);
      expect(body['notes'], 'Session notes');
      expect(body['exercises'], [
        {
          'exerciseName': 'Squat',
          'sets': 3,
          'reps': 10,
          'weight': null,
          'notes': null,
        },
      ]);
    },
  );

  testWidgets('existing HasTrainingReport hides creation without navigation', (
    tester,
  ) async {
    final fixture = ReportFixture(hasReport: true);
    final observer = RouteObserverFixture();
    await showDetails(tester, fixture, observer: observer);
    expect(find.text('Member One'), findsOneWidget);
    expect(find.text('Add Training Report'), findsNothing);
    expect(find.byType(AddTrainingReportScreen), findsNothing);
    expect(observer.pushed, hasLength(1));
    expect(fixture.reportsSaved, 0);
  });

  testWidgets(
    'report return after Client Details disposal does not refresh disposed state',
    (tester) async {
      final fixture = ReportFixture();
      final observer = RouteObserverFixture();
      final navigatorKey = GlobalKey<NavigatorState>();
      await showDetails(
        tester,
        fixture,
        observer: observer,
        navigatorKey: navigatorKey,
        launcher: true,
      );
      final detailsRoute = observer.pushed.last;
      await tap(tester, 'Add Training Report');
      navigatorKey.currentState!.removeRoute(detailsRoute);
      await tester.pumpAndSettle();
      expect(find.byType(AddTrainingReportScreen), findsOneWidget);
      navigatorKey.currentState!.pop(true);
      await tester.pumpAndSettle();
      expect(find.text('Open client'), findsOneWidget);
      expect(fixture.detailLoads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a retained report action cannot navigate after screen disposal',
    (tester) async {
      final fixture = ReportFixture();
      final observer = RouteObserverFixture();
      await showDetails(tester, fixture, observer: observer);
      final action = reportAction(tester);
      await tester.pumpWidget(const SizedBox());
      action();
      await tester.pump();
      expect(observer.pushed, hasLength(1));
      expect(fixture.detailLoads, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
