import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/screens/group_training_details_screen.dart';
import 'package:ironbook_mobile/screens/recommendations_screen.dart';
import 'package:ironbook_mobile/screens/trainer_details_screen.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';
import 'package:ironbook_mobile/theme/ironbook_mobile_theme.dart';

Map<String, Object?> responseData({
  int centerId = 7,
  bool empty = false,
  bool personalized = true,
}) => {
  'centerId': centerId,
  'centerName': 'Selected center',
  'isPersonalized': personalized,
  'trainers': empty
      ? []
      : [
          {
            'id': 11,
            'name': 'Trainer One',
            'categories': ['strength'],
            'similarity': personalized ? 0.75 : null,
            'approvedCoachingRequestCount': 3,
          },
        ],
  'groupTrainings': empty
      ? []
      : [
          {
            'id': 22,
            'name': 'Session One',
            'trainerName': 'Trainer One',
            'category': 'conditioning',
            'startsAt': '2030-01-15T10:00:00Z',
            'capacity': 10,
            'enrollmentCount': 4,
            'fillRatio': 0.4,
            'similarity': personalized ? 0.5 : null,
          },
        ],
};

Future<void> showScreen(
  WidgetTester tester,
  CenterApiService api, {
  int centerId = 7,
}) async {
  await tester.binding.setSurfaceSize(const Size(500, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: IronBookMobileTheme.theme,
      home: RecommendationsScreen(
        centerId: centerId,
        centerName: 'Selected center',
        centerApiService: api,
      ),
    ),
  );
}

void main() {
  test('requests selected center and rejects mismatched center data', () async {
    var mismatch = false;
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/member/centers/7/recommendations');
      return http.Response(
        jsonEncode(responseData(centerId: mismatch ? 8 : 7)),
        200,
      );
    });
    addTearDown(client.close);
    final api = CenterApiService(
      client: client,
      apiBaseUrl: 'http://localhost',
    );
    final data = await api.getRecommendationsForCenter(7);
    expect(data.trainers.single.similarity, 0.75);
    expect(data.groupTrainings.single.enrollmentCount, 4);
    mismatch = true;
    await expectLater(
      api.getRecommendationsForCenter(7),
      throwsA(isA<CenterApiException>()),
    );
  });

  testWidgets('loading, error, retry and independent empty sections', (
    tester,
  ) async {
    var calls = 0;
    final client = MockClient(
      (request) async => ++calls == 1
          ? http.Response('', 500)
          : http.Response(
              jsonEncode(responseData(empty: true, personalized: false)),
              200,
            ),
    );
    addTearDown(client.close);
    await showScreen(
      tester,
      CenterApiService(client: client, apiBaseUrl: 'http://localhost'),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Recommendations unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.text('No trainer recommendations available for this center.'),
      findsOneWidget,
    );
    expect(
      find.text('No group training recommendations available for this center.'),
      findsOneWidget,
    );
    expect(find.text('Popular at this center'), findsOneWidget);
    expect(find.textContaining('Recommendation score:'), findsNothing);
  });

  testWidgets(
    'real fields and scores; details use selected center and item IDs',
    (tester) async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return request.url.path.endsWith('/recommendations')
            ? http.Response(jsonEncode(responseData()), 200)
            : http.Response('', 404);
      });
      addTearDown(client.close);
      await showScreen(
        tester,
        CenterApiService(client: client, apiBaseUrl: 'http://localhost'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recommendation score: 0.750'), findsOneWidget);
      expect(find.text('Recommendation score: 0.500'), findsOneWidget);
      expect(find.text('Enrolled: 4/10'), findsOneWidget);
      await tester.tap(find.text('View trainer'));
      await tester.pumpAndSettle();
      final trainer = tester.widget<TrainerDetailsScreen>(
        find.byType(TrainerDetailsScreen),
      );
      expect(trainer.centerId, 7);
      expect(trainer.trainerId, 11);
      expect(paths, contains('/api/centers/7/trainers/11'));
      Navigator.of(tester.element(find.byType(TrainerDetailsScreen))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('View group training'));
      await tester.pumpAndSettle();
      final training = tester.widget<GroupTrainingDetailsScreen>(
        find.byType(GroupTrainingDetailsScreen),
      );
      expect(training.centerId, 7);
      expect(training.groupTrainingId, 22);
      expect(paths, contains('/api/centers/7/group-trainings/22'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing center reloads and null scores stay hidden', (
    tester,
  ) async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      final id = int.parse(request.url.pathSegments[3]);
      return http.Response(
        jsonEncode(responseData(centerId: id, personalized: false)),
        200,
      );
    });
    addTearDown(client.close);
    final api = CenterApiService(
      client: client,
      apiBaseUrl: 'http://localhost',
    );
    await showScreen(tester, api);
    await tester.pumpAndSettle();
    expect(find.text('Trainer One'), findsOneWidget);
    expect(find.textContaining('Recommendation score:'), findsNothing);
    await showScreen(tester, api, centerId: 8);
    await tester.pumpAndSettle();
    expect(paths, [
      '/api/member/centers/7/recommendations',
      '/api/member/centers/8/recommendations',
    ]);
    expect(find.text('Session One'), findsOneWidget);
  });
}
