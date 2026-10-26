import 'support/paged_fixture.dart';

import 'dart:convert';

import 'support/token_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/screens/center_list_screen.dart';
import 'package:ironbook_mobile/screens/my_trainings_screen.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';
import 'package:ironbook_mobile/theme/ironbook_mobile_theme.dart';

Map<String, Object?> training({int id = 1, String status = 'Pending'}) => {
  'id': id,
  'centerId': 3,
  'centerName': 'Selected center',
  'trainerProfileId': 4,
  'trainerName': 'Trainer $id',
  'memberProfileId': 5,
  'requestedStartAt': '2030-01-15T10:00:00Z',
  'durationMinutes': 60,
  'status': status,
  'fitnessGoal': 'Build Strength',
  'note': 'Session note',
  'createdAt': '2030-01-01T10:00:00Z',
};

CenterApiService apiFor(http.Client client) => CenterApiService(
  client: client,
  apiBaseUrl: 'http://localhost',
  accessTokenProvider: FakeAccessTokenProvider(),
);

Future<void> showScreen(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(500, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(theme: IronBookMobileTheme.theme, home: screen),
  );
}

Future<void> confirmCancel(WidgetTester tester) async {
  await tester.tap(
    find.widgetWithText(OutlinedButton, 'Cancel training').first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Cancel training'));
  await tester.pumpAndSettle();
}

void main() {
  test('GET preserves API order and sends optional status filter; POST confirms cancellation', () async {
    final queries = <Map<String, String>>[];
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        expect(request.url.path, '/api/member/my-trainings');
        queries.add(request.url.queryParameters);
        return http.Response(
          jsonEncode(paged([training(id: 2), training(id: 1)])),
          200,
        );
      }
      expect(request.method, 'POST');
      expect(request.url.path, '/api/member/my-trainings/1/cancel');
      return http.Response(jsonEncode(training(status: 'Cancelled')), 200);
    });
    addTearDown(client.close);
    final api = apiFor(client);
    expect((await api.getMyTrainings()).items.map((item) => item.id), [2, 1]);
    await api.getMyTrainings(status: 'Approved');
    expect(queries, [
      {'pageNumber': '1', 'pageSize': '20'},
      {'pageNumber': '1', 'pageSize': '20', 'status': 'Approved'},
    ]);
    expect((await api.cancelMyTraining(1)).status, 'Cancelled');
  });

  test('cancel rejects conflicts, missing requests and unconfirmed success responses', () async {
    var code = 409;
    final client = MockClient(
      (request) async => http.Response(jsonEncode(training()), code),
    );
    addTearDown(client.close);
    final api = apiFor(client);
    for (final status in [409, 404, 500, 200]) {
      code = status;
      await expectLater(
        api.cancelMyTraining(1),
        throwsA(isA<CenterApiException>()),
      );
    }
  });

  testWidgets(
    'loading, error, retry, empty, refresh and all requested fields',
    (tester) async {
      var gets = 0;
      final client = MockClient((request) async {
        gets++;
        if (gets == 1) return http.Response('', 500);
        return http.Response(
          jsonEncode(paged(gets == 2 ? [] : [training()])),
          200,
        );
      });
      addTearDown(client.close);
      await showScreen(
        tester,
        MyTrainingsScreen(centerApiService: apiFor(client)),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('My trainings unavailable'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No training requests yet.'), findsOneWidget);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      for (final text in [
        'Trainer 1',
        'Selected center',
        'Duration: 60 minutes',
        'Build Strength',
        'Session note',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.textContaining('Date/time:'), findsOneWidget);
    },
  );

  testWidgets(
    'cancel controls exist only for Pending and Approved; API order stays unchanged',
    (tester) async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode(
            paged([
              training(id: 2, status: 'Approved'),
              training(id: 1),
              training(id: 3, status: 'Rejected'),
              training(id: 4, status: 'Cancelled'),
            ]),
          ),
          200,
        ),
      );
      addTearDown(client.close);
      await showScreen(
        tester,
        MyTrainingsScreen(centerApiService: apiFor(client)),
      );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(OutlinedButton, 'Cancel training'),
        findsNWidgets(2),
      );
      expect(
        tester.getTopLeft(find.text('Trainer 2')).dy,
        lessThan(tester.getTopLeft(find.text('Trainer 1')).dy),
      );
      for (final id in [3, 4]) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('training-$id')),
            matching: find.text('Cancel training'),
          ),
          findsNothing,
        );
      }
    },
  );

  testWidgets(
    'requires confirmation and refreshes the selected filter after success',
    (tester) async {
      var cancelled = false;
      var posts = 0;
      final queries = <String?>[];
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          cancelled = true;
          return http.Response(jsonEncode(training(status: 'Cancelled')), 200);
        }
        queries.add(request.url.queryParameters['status']);
        return http.Response(
          jsonEncode(paged(cancelled ? [] : [training()])),
          200,
        );
      });
      addTearDown(client.close);
      await showScreen(
        tester,
        MyTrainingsScreen(centerApiService: apiFor(client)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Pending'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel training'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(posts, 0);
      await tester.tap(find.text('Keep training'));
      await tester.pumpAndSettle();
      expect(posts, 0);
      await confirmCancel(tester);
      expect(posts, 1);
      expect(queries, [null, 'Pending', 'Pending']);
      expect(find.text('Training cancelled.'), findsOneWidget);
      expect(find.text('No pending training requests.'), findsOneWidget);
    },
  );

  testWidgets('failed cancellation keeps the request and offers refresh', (
    tester,
  ) async {
    final client = MockClient(
      (request) async => request.method == 'POST'
          ? http.Response('', 409)
          : http.Response(jsonEncode(paged([training()])), 200),
    );
    addTearDown(client.close);
    await showScreen(
      tester,
      MyTrainingsScreen(centerApiService: apiFor(client)),
    );
    await tester.pumpAndSettle();
    await confirmCancel(tester);
    expect(find.textContaining('can no longer be cancelled'), findsOneWidget);
    expect(find.byKey(const ValueKey('training-1')), findsOneWidget);
    expect(find.text('Training cancelled.'), findsNothing);
    expect(find.text('Refresh'), findsOneWidget);
  });

  testWidgets(
    'a refresh failure after successful cancellation stays a load error',
    (tester) async {
      var cancelled = false;
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          cancelled = true;
          return http.Response(jsonEncode(training(status: 'Cancelled')), 200);
        }
        return cancelled
            ? http.Response('', 500)
            : http.Response(jsonEncode(paged([training()])), 200);
      });
      addTearDown(client.close);
      await showScreen(
        tester,
        MyTrainingsScreen(centerApiService: apiFor(client)),
      );
      await tester.pumpAndSettle();
      await confirmCancel(tester);
      expect(find.text('Training cancelled.'), findsOneWidget);
      expect(find.text('My trainings unavailable'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.textContaining('Training could not be cancelled'),
        findsNothing,
      );
    },
  );

  testWidgets('member home opens My Trainings', (tester) async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      return http.Response(memberListBody(request, []), 200);
    });
    addTearDown(client.close);
    await showScreen(
      tester,
      CenterListScreen(centerApiService: apiFor(client)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Trainings'));
    await tester.pumpAndSettle();
    expect(find.byType(MyTrainingsScreen), findsOneWidget);
    expect(paths, contains('/api/member/my-trainings'));
  });
}
