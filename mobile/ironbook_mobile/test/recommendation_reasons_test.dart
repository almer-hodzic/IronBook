import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/models/member_recommendations.dart';
import 'package:ironbook_mobile/screens/group_training_details_screen.dart';
import 'package:ironbook_mobile/screens/trainer_details_screen.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';

import 'member_discovery_bearer_test.dart' show groupJson;
import 'recommendations_test.dart' show responseData, showScreen;
import 'support/token_provider.dart';

const trainerReasons = [
  'Matches your strength preference.',
  '3 approved coaching requests in this center.',
];
const groupReasons = [
  'Matches your conditioning preference.',
  '4 of 10 places enrolled.',
];

Map<String, Object?> trainerJson(Map<String, Object?> data) =>
    (data['trainers'] as List).first as Map<String, Object?>;

Map<String, Object?> trainingJson(Map<String, Object?> data) =>
    (data['groupTrainings'] as List).first as Map<String, Object?>;

Map<String, Object?> explainedData({bool personalized = true}) {
  final data = responseData(personalized: personalized);
  trainerJson(data)['reasons'] = trainerReasons;
  trainingJson(data)['reasons'] = groupReasons;
  return data;
}

CenterApiService apiFor(http.Client client) {
  addTearDown(client.close);
  return CenterApiService(
    client: client,
    apiBaseUrl: 'http://localhost',
    accessTokenProvider: FakeAccessTokenProvider(),
  );
}

CenterApiService apiForData(Map<String, Object?> data) => apiFor(
  MockClient((request) async {
    expect(request.method, 'GET');
    expect(request.url.path, '/api/member/centers/7/recommendations');
    expect(request.url.hasQuery, isFalse);
    expect(request.body, isEmpty);
    expect(request.headers['Authorization'], 'Bearer fixture-access-token');
    return http.Response(jsonEncode(data), 200);
  }),
);

Future<void> tapLabel(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  test('Trainer parses reasons verbatim in backend order', () {
    final json = trainerJson(responseData());
    final reasons = trainerReasons.reversed.toList();
    json['reasons'] = reasons;
    final trainer = TrainerRecommendation.fromJson(json);
    expect(trainer.reasons, reasons);
    expect(trainer.similarity, 0.75);
    expect(trainer.categories, ['strength']);
    expect(trainer.approvedCoachingRequestCount, 3);
  });

  test('Group parses reasons verbatim in backend order', () {
    final json = trainingJson(responseData());
    final reasons = groupReasons.reversed.toList();
    json['reasons'] = reasons;
    final training = GroupTrainingRecommendation.fromJson(json);
    expect(training.reasons, reasons);
    expect(training.similarity, 0.5);
    expect(training.fillRatio, 0.4);
    expect(training.startsAt, DateTime.utc(2030, 1, 15, 10));
  });

  for (final value in ['missing', 'empty', 'null']) {
    test('$value reasons safely parse as empty in both models', () {
      final data = responseData(personalized: false);
      if (value != 'missing') {
        trainerJson(data)['reasons'] = value == 'empty' ? [] : null;
        trainingJson(data)['reasons'] = value == 'empty' ? [] : null;
      }
      final result = MemberRecommendations.fromJson(data);
      expect(result.trainers.single.reasons, isEmpty);
      expect(result.groupTrainings.single.reasons, isEmpty);
      expect(result.trainers.single.similarity, isNull);
      expect(result.groupTrainings.single.similarity, isNull);
    });
  }

  for (final invalid in <Object>[
    'not a list',
    <Object>['Valid text', 42],
  ]) {
    test('malformed reasons $invalid follow existing format errors', () async {
      final data = responseData();
      trainerJson(data)['reasons'] = invalid;
      expect(
        () => TrainerRecommendation.fromJson(trainerJson(data)),
        throwsFormatException,
      );
      trainerJson(data)['reasons'] = [];
      trainingJson(data)['reasons'] = invalid;
      expect(
        () => GroupTrainingRecommendation.fromJson(trainingJson(data)),
        throwsFormatException,
      );
      await expectLater(
        apiForData(data).getRecommendationsForCenter(7),
        throwsA(isA<CenterApiException>()),
      );
    });
  }

  testWidgets('both cards render multiple reasons in order with raw scores', (
    tester,
  ) async {
    await showScreen(tester, apiForData(explainedData()));
    await tester.pumpAndSettle();
    for (final reasons in [trainerReasons, groupReasons]) {
      for (final reason in reasons) {
        expect(find.text(reason), findsOneWidget);
      }
      expect(
        tester.getTopLeft(find.text(reasons.first)).dy,
        lessThan(tester.getTopLeft(find.text(reasons.last)).dy),
      );
    }
    expect(find.text('Recommendation score: 0.750'), findsOneWidget);
    expect(find.text('Recommendation score: 0.500'), findsOneWidget);
    expect(find.text('Enrolled: 4/10'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final missing in [false, true]) {
    testWidgets('empty explanation UI is absent (missing: $missing)', (
      tester,
    ) async {
      final data = responseData();
      if (!missing) {
        trainerJson(data)['reasons'] = [];
        trainingJson(data)['reasons'] = [];
      }
      await showScreen(tester, apiForData(data));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('trainer-reasons-11')), findsNothing);
      expect(find.byKey(const ValueKey('group-reasons-22')), findsNothing);
      expect(find.textContaining('Matches your'), findsNothing);
      expect(find.text(trainerReasons.last), findsNothing);
      expect(find.text(groupReasons.last), findsNothing);
      expect(find.text('Trainer One'), findsOneWidget);
      expect(find.text('Session One'), findsOneWidget);
      expect(find.text('Recommendation score: 0.750'), findsOneWidget);
    });
  }

  testWidgets(
    'fallback displays only supplied facts and hides null similarity',
    (tester) async {
      final data = responseData(personalized: false);
      trainerJson(data)['reasons'] = [trainerReasons.last];
      trainingJson(data)['reasons'] = [groupReasons.last];
      await showScreen(tester, apiForData(data));
      await tester.pumpAndSettle();
      expect(find.text(trainerReasons.last), findsOneWidget);
      expect(find.text(groupReasons.last), findsOneWidget);
      expect(find.textContaining('Matches your'), findsNothing);
      expect(find.textContaining('Recommendation score:'), findsNothing);
      expect(find.text('Popular at this center'), findsOneWidget);
    },
  );

  testWidgets('both collections render backend order without local ranking', (
    tester,
  ) async {
    final data = explainedData();
    final trainers = data['trainers'] as List;
    trainers.insert(0, {
      ...trainerJson(data),
      'id': 99,
      'name': 'Backend first trainer',
      'similarity': 0.0,
    });
    final groups = data['groupTrainings'] as List;
    groups.insert(0, {
      ...trainingJson(data),
      'id': 98,
      'name': 'Backend first group',
      'startsAt': '2031-01-15T10:00:00Z',
      'similarity': 0.0,
    });
    final api = apiForData(data);
    final result = await api.getRecommendationsForCenter(7);
    expect(result.trainers.map((trainer) => trainer.id), [99, 11]);
    expect(result.groupTrainings.map((group) => group.id), [98, 22]);
    await showScreen(tester, api);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Backend first trainer')).dy,
      lessThan(tester.getTopLeft(find.text('Trainer One')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Backend first group')).dy,
      lessThan(tester.getTopLeft(find.text('Session One')).dy),
    );
  });

  testWidgets('reason cards retain Trainer and Group enrollment navigation', (
    tester,
  ) async {
    var recommendationLoads = 0;
    var enrolled = false;
    var enrollments = 0;
    final client = MockClient((request) async {
      expect(
        request.headers['Authorization'],
        request.url.path == '/api/centers/7/trainers/11'
            ? isNull
            : 'Bearer fixture-access-token',
      );
      expect(request.url.hasQuery, isFalse);
      switch ((request.method, request.url.path)) {
        case ('GET', '/api/member/centers/7/recommendations'):
          recommendationLoads++;
          return http.Response(jsonEncode(explainedData()), 200);
        case ('GET', '/api/centers/7/trainers/11'):
          return http.Response('', 404);
        case ('GET', '/api/centers/7/group-trainings/22'):
          return http.Response(
            jsonEncode({
              ...groupJson,
              'enrolledCount': enrolled ? 5 : 4,
              'availableSpots': enrolled ? 5 : 6,
              'isEnrolled': enrolled,
            }),
            200,
          );
        case ('POST', '/api/centers/7/group-trainings/22/enroll'):
          expect(jsonDecode(request.body), isEmpty);
          enrolled = true;
          enrollments++;
          return http.Response(
            jsonEncode({
              'id': 5,
              'groupTrainingId': 22,
              'memberProfileId': 6,
              'status': 'Enrolled',
              'enrolledAt': '2030-01-01T10:00:00Z',
            }),
            201,
          );
        default:
          throw StateError('Unexpected request: ${request.url}');
      }
    });
    await showScreen(tester, apiFor(client));
    await tester.pumpAndSettle();
    await tapLabel(tester, 'View trainer');
    final trainer = tester.widget<TrainerDetailsScreen>(
      find.byType(TrainerDetailsScreen),
    );
    expect(trainer.centerId, 7);
    expect(trainer.trainerId, 11);
    Navigator.of(tester.element(find.byType(TrainerDetailsScreen))).pop();
    await tester.pumpAndSettle();
    await tapLabel(tester, 'View group training');
    final group = tester.widget<GroupTrainingDetailsScreen>(
      find.byType(GroupTrainingDetailsScreen),
    );
    expect(group.centerId, 7);
    expect(group.groupTrainingId, 22);
    await tapLabel(tester, 'Join Training');
    expect(enrollments, 1);
    expect(find.text('You are enrolled in this class.'), findsOneWidget);
    Navigator.of(tester.element(find.byType(GroupTrainingDetailsScreen))).pop();
    await tester.pumpAndSettle();
    expect(recommendationLoads, 3);
    expect(find.text(trainerReasons.first), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long backend reasons wrap within a narrow card body', (
    tester,
  ) async {
    final data = explainedData();
    final longReason = List.filled(4, trainerReasons.last).join(' ');
    trainerJson(data)['reasons'] = [longReason];
    await showScreen(tester, apiForData(data));
    await tester.pumpAndSettle();
    final finder = find.byKey(const ValueKey('trainer-reasons-11'));
    final reasons = tester.widget<Widget>(finder);
    final theme = Theme.of(tester.element(finder));
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('reason-layout-harness'),
        theme: theme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 260, child: reasons),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(longReason), findsOneWidget);
    expect(tester.widget<Text>(find.text(longReason)).maxLines, isNull);
    expect(tester.getSize(find.text(longReason)).height, greaterThan(30));
    expect(tester.takeException(), isNull);
  });
}
