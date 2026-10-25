import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironbook_mobile/screens/center_list_screen.dart';
import 'package:ironbook_mobile/screens/member_profile_screen.dart';
import 'package:ironbook_mobile/services/center_api_service.dart';
import 'package:ironbook_mobile/theme/ironbook_mobile_theme.dart';

import 'support/token_provider.dart';

Map<String, Object?> profile() => {
  'id': 7,
  'firstName': 'Mira',
  'lastName': 'Test',
  'email': 'mira@example.com',
  'phoneNumber': '061123456',
  'isActive': true,
  'createdAt': '2026-01-15T10:00:00Z',
};

Future<void> showScreen(
  WidgetTester tester,
  http.Client client, {
  bool home = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(500, 1500));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(client.close);
  final api = CenterApiService(
    client: client,
    apiBaseUrl: 'http://localhost',
    accessTokenProvider: FakeAccessTokenProvider(),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: IronBookMobileTheme.theme,
      home: home
          ? CenterListScreen(centerApiService: api)
          : MemberProfileScreen(centerApiService: api),
    ),
  );
}

Finder field(String name) => find.byKey(Key('profile-$name'));
Future<void> edit(WidgetTester tester) async {
  await tester.tap(find.text('Edit profile'));
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save changes'));
  await tester.tap(find.text('Save changes'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads and displays real response fields', (tester) async {
    final response = Completer<http.Response>();
    await showScreen(
      tester,
      MockClient((request) {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/member/profile');
        return response.future;
      }),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    response.complete(http.Response(jsonEncode(profile()), 200));
    await tester.pumpAndSettle();
    for (final value in [
      'Mira',
      'Test',
      'mira@example.com',
      '061123456',
      'Account active',
      'Created date',
    ]) {
      expect(find.text(value), findsOneWidget);
    }
    expect(find.textContaining('2026'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('home Profile navigation opens the API screen', (tester) async {
    await showScreen(
      tester,
      MockClient(
        (request) async => http.Response(
          request.url.path == '/api/member/profile'
              ? jsonEncode(profile())
              : '[]',
          200,
        ),
      ),
      home: true,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.byType(MemberProfileScreen), findsOneWidget);
    expect(find.text('mira@example.com'), findsOneWidget);
  });

  testWidgets(
    'load error offers retry; missing optional phone and inactive status display',
    (tester) async {
      var gets = 0;
      await showScreen(
        tester,
        MockClient((request) async {
          gets++;
          return gets == 1
              ? http.Response('', 500)
              : http.Response(
                  jsonEncode({
                    ...profile(),
                    'phoneNumber': null,
                    'isActive': false,
                  }),
                  200,
                );
        }),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be loaded'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Not provided'), findsOneWidget);
      expect(find.text('Account inactive'), findsOneWidget);
    },
  );

  testWidgets('required names and email are validated after trimming', (
    tester,
  ) async {
    var puts = 0;
    await showScreen(
      tester,
      MockClient((request) async {
        if (request.method == 'PUT') puts++;
        return http.Response(jsonEncode(profile()), 200);
      }),
    );
    await tester.pumpAndSettle();
    await edit(tester);
    expect(
      tester.widget<TextFormField>(field('first-name')).controller!.text,
      'Mira',
    );
    for (final name in ['first-name', 'last-name', 'email']) {
      await tester.enterText(field(name), '   ');
    }
    await save(tester);
    for (final label in ['First name', 'Last name', 'Email']) {
      expect(find.text('$label is required.'), findsOneWidget);
    }
    expect(puts, 0);
  });

  testWidgets('invalid email prevents a PUT', (tester) async {
    var puts = 0;
    await showScreen(
      tester,
      MockClient((request) async {
        if (request.method == 'PUT') puts++;
        return http.Response(jsonEncode(profile()), 200);
      }),
    );
    await tester.pumpAndSettle();
    await edit(tester);
    for (final invalid in ['invalid', 'a@@example.com', 'a b@example.com']) {
      await tester.enterText(field('email'), invalid);
      await save(tester);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
    }
    expect(puts, 0);
  });

  testWidgets(
    'successful PUT trims only editable fields, prevents duplicate saves and refreshes after email change',
    (tester) async {
      var saved = profile();
      var puts = 0;
      var gets = 0;
      final pending = Completer<http.Response>();
      await showScreen(
        tester,
        MockClient((request) async {
          expect(request.url.path, '/api/member/profile');
          expect(request.url.queryParameters, isEmpty);
          if (request.method == 'GET') {
            gets++;
            return http.Response(jsonEncode(saved), 200);
          }
          expect(request.method, 'PUT');
          puts++;
          expect(jsonDecode(request.body), {
            'firstName': 'Mina',
            'lastName': 'Updated',
            'email': 'updated@example.com',
            'phoneNumber': null,
          });
          saved = {
            ...saved,
            ...jsonDecode(request.body) as Map<String, dynamic>,
          };
          return pending.future;
        }),
      );
      await tester.pumpAndSettle();
      await edit(tester);
      await tester.enterText(field('first-name'), ' Mina ');
      await tester.enterText(field('last-name'), ' Updated ');
      await tester.enterText(field('email'), ' updated@example.com ');
      await tester.enterText(field('phone'), '  ');
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      expect(find.text('Saving...'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Saving...'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.widget<TextFormField>(field('email')).enabled, isFalse);
      expect(puts, 1);
      pending.complete(http.Response(jsonEncode(saved), 200));
      await tester.pumpAndSettle();
      expect(find.text('Profile saved successfully.'), findsOneWidget);
      expect(find.text('updated@example.com'), findsOneWidget);
      expect(find.text('Mina'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(gets, 2);
      expect(find.text('updated@example.com'), findsOneWidget);
    },
  );

  testWidgets('failed update preserves all values and supports retry', (
    tester,
  ) async {
    var puts = 0;
    await showScreen(
      tester,
      MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(jsonEncode(profile()), 200);
        }
        puts++;
        if (puts == 1) {
          return http.Response(
            jsonEncode({
              'errors': {
                'Email': ['Email could not be saved.'],
              },
            }),
            400,
          );
        }
        return http.Response(
          jsonEncode({
            ...profile(),
            ...jsonDecode(request.body) as Map<String, dynamic>,
          }),
          200,
        );
      }),
    );
    await tester.pumpAndSettle();
    await edit(tester);
    final entered = {
      'first-name': 'New first',
      'last-name': 'New last',
      'email': 'new@example.com',
      'phone': '555123',
    };
    for (final entry in entered.entries) {
      await tester.enterText(field(entry.key), entry.value);
    }
    await save(tester);
    expect(find.text('Email could not be saved.'), findsOneWidget);
    for (final entry in entered.entries) {
      expect(
        tester.widget<TextFormField>(field(entry.key)).controller!.text,
        entry.value,
      );
    }
    await save(tester);
    expect(puts, 2);
    expect(find.text('Profile saved successfully.'), findsOneWidget);
  });
}
