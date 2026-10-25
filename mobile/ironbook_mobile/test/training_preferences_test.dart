import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/models/training_preferences.dart';
import 'package:ironbook_mobile/screens/training_preferences_screen.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';
import 'package:ironbook_mobile/theme/ironbook_mobile_theme.dart';

import 'support/token_provider.dart';

Future<void> showScreen(WidgetTester tester, http.Client client) async {
  await tester.binding.setSurfaceSize(const Size(500, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: IronBookMobileTheme.theme,
      home: TrainingPreferencesScreen(
        centerApiService: CenterApiService(
          accessTokenProvider: FakeAccessTokenProvider(),
          client: client,
          apiBaseUrl: 'http://localhost',
        ),
      ),
    ),
  );
}

void main() {
  test(
    'GET handles missing preferences and PUT sends the API contract',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/member/training-preferences');
        if (request.method == 'GET') return http.Response('', 404);
        expect(request.method, 'PUT');
        expect(request.headers['content-type'], 'application/json');
        expect(jsonDecode(request.body), {
          'primaryGoal': 'Build Strength',
          'interests': ['strength', 'fat_loss'],
        });
        return http.Response(request.body, 200);
      });
      final api = CenterApiService(
        accessTokenProvider: FakeAccessTokenProvider(),
        client: client,
        apiBaseUrl: 'http://localhost',
      );
      expect(await api.getTrainingPreferences(), isNull);
      final saved = await api.saveTrainingPreferences(
        const TrainingPreferences(
          primaryGoal: 'Build Strength',
          interests: ['strength', 'fat_loss'],
        ),
      );
      expect(saved.primaryGoal, 'Build Strength');
      expect(saved.interests, ['strength', 'fat_loss']);
      client.close();
    },
  );

  testWidgets('loading, required goal, two-interest limit and save success', (
    tester,
  ) async {
    final load = Completer<http.Response>();
    Map<String, dynamic>? saved;
    final client = MockClient((request) async {
      if (request.method == 'GET') return load.future;
      saved = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(request.body, 200);
    });
    addTearDown(client.close);
    await showScreen(tester, client);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    load.complete(http.Response('', 404));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save preferences'));
    await tester.pumpAndSettle();
    expect(find.text('Select a primary goal.'), findsOneWidget);
    expect(saved, isNull);
    await tester.tap(find.text('Build Strength'));
    await tester.tap(find.text('Strength'));
    await tester.tap(find.text('Conditioning'));
    await tester.tap(find.text('Performance'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Select at most two interests.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Performance'))
          .selected,
      isFalse,
    );
    await tester.tap(find.text('Save preferences'));
    await tester.pumpAndSettle();
    expect(saved, {
      'primaryGoal': 'Build Strength',
      'interests': ['strength', 'conditioning'],
    });
    expect(find.text('Training preferences saved.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'load retry restores selections; failed save keeps edits for retry',
    (tester) async {
      var loads = 0;
      var saves = 0;
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          if (++loads == 1) return http.Response('', 500);
          return http.Response(
            jsonEncode({
              'primaryGoal': 'Lose Fat',
              'interests': ['fat_loss'],
            }),
            200,
          );
        }
        if (++saves == 1) {
          return http.Response(
            jsonEncode({
              'errors': {
                'PrimaryGoal': ['Save rejected.'],
              },
            }),
            400,
          );
        }
        return http.Response(request.body, 200);
      });
      addTearDown(client.close);
      await showScreen(tester, client);
      await tester.pumpAndSettle();
      expect(find.text('Preferences unavailable'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Lose Fat'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Fat Loss'))
            .selected,
        isTrue,
      );
      await tester.tap(find.text('Improve Performance'));
      await tester.tap(find.text('Save preferences'));
      await tester.pumpAndSettle();
      expect(find.text('Save rejected.'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Improve Performance'),
            )
            .selected,
        isTrue,
      );
      await tester.tap(find.text('Save preferences'));
      await tester.pumpAndSettle();
      expect(find.text('Training preferences saved.'), findsOneWidget);
      expect(find.text('Save rejected.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
