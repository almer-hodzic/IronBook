import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ironbook_admin/screens/admin_shell.dart';

import 'support/auth_fixture.dart';

void main() {
  late AuthFixture fixture;
  setUp(() => fixture = AuthFixture());
  Finder getUsername() => find.widgetWithText(TextFormField, 'Username');
  Finder getPassword() => find.widgetWithText(TextFormField, 'Password');
  Finder getSubmit() => find.widgetWithText(FilledButton, 'Log in');
  Future<void> start(WidgetTester tester) async {
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(getUsername(), '  fixture-user  ');
    await tester.enterText(getPassword(), 'transient-private-password');
  }

  void expectLogin() {
    expect(getUsername(), findsOneWidget);
    expect(getPassword(), findsOneWidget);
    expect(getSubmit(), findsOneWidget);
    expect(find.byType(AdminShell), findsNothing);
  }

  testWidgets('no session shows Login with username and obscured password', (
    tester,
  ) async {
    await start(tester);
    expectLogin();
    final editable = tester.widget<EditableText>(
      find.descendant(of: getPassword(), matching: find.byType(EditableText)),
    );
    expect(editable.obscureText, isTrue);
    expect(editable.autofillHints, isNull);
    expect(fixture.requests, isEmpty);
  });

  testWidgets('startup shows loading until session restoration completes', (
    tester,
  ) async {
    fixture.storage.pendingRead = Completer<String?>();
    await tester.pumpWidget(fixture.app());
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(getUsername(), findsNothing);
    fixture.storage.pendingRead!.complete(null);
    await tester.pumpAndSettle();
    expectLogin();
  });

  void expectRoleRoot(String role) {
    expect(
      find.byType(AdminShell),
      role == 'Admin' ? findsOneWidget : findsNothing,
    );
    expect(
      find.text('This account cannot use this app.'),
      role == 'Admin' ? findsNothing : findsOneWidget,
    );
  }

  for (final role in ['Member', 'Trainer', 'Admin', 'Unknown']) {
    testWidgets(
      'restored $role session selects only its supported platform root',
      (tester) async {
        fixture.persist(role: role);
        await start(tester);
        expectRoleRoot(role);
        expect(getUsername(), findsNothing);
        expect(fixture.requests, isEmpty);
      },
    );
  }

  testWidgets('expired persisted session is cleared and shows Login', (
    tester,
  ) async {
    fixture.persist(expired: true);
    await start(tester);
    expectLogin();
    expect(fixture.storage.value, isNull);
    expect(fixture.requests, isEmpty);
  });

  testWidgets('malformed persisted session is cleared and shows Login', (
    tester,
  ) async {
    fixture.storage.value = '{broken';
    await start(tester);
    expectLogin();
    expect(fixture.storage.value, isNull);
  });

  testWidgets('storage failure shows safe retry; retry restores normally', (
    tester,
  ) async {
    fixture.storage.failRead = true;
    await start(tester);
    expect(
      find.text('Unable to restore your session. Please try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Private storage'), findsNothing);
    fixture.storage.failRead = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expectLogin();
  });

  testWidgets('required username/password prevent a request', (tester) async {
    await start(tester);
    await tester.tap(getSubmit());
    await tester.pumpAndSettle();
    expect(find.text('Enter your username.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(fixture.requests, isEmpty);
  });

  testWidgets(
    'successful login persists session and enters existing root without persisting password',
    (tester) async {
      await start(tester);
      await fill(tester);
      await tester.tap(getSubmit());
      await tester.pumpAndSettle();
      expect(find.byType(AdminShell), findsOneWidget);
      expect(getPassword(), findsNothing);
      final request = fixture.requests.single;
      expect(request.url.path, '/api/auth/login');
      expect(jsonDecode(request.body), {
        'username': 'fixture-user',
        'password': 'transient-private-password',
      });
      expect(jsonDecode(fixture.storage.value!), fixture.session());
      expect(
        fixture.storage.value,
        isNot(contains('transient-private-password')),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final failure in ['credentials', 'offline', 'malformed']) {
    testWidgets('$failure login failure remains on Login with safe error', (
      tester,
    ) async {
      fixture.respond = (_) async => switch (failure) {
        'credentials' => http.Response(
          '{"detail":"PRIVATE backend detail"}',
          401,
        ),
        'offline' => throw http.ClientException('PRIVATE network detail'),
        _ => http.Response('{"accessToken":"PRIVATE"}', 200),
      };
      await start(tester);
      await fill(tester);
      await tester.tap(getSubmit());
      await tester.pumpAndSettle();
      expectLogin();
      expect(find.byKey(const ValueKey('login-error')), findsOneWidget);
      expect(find.textContaining('PRIVATE'), findsNothing);
      expect(fixture.storage.value, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'loading disables inputs and duplicate button/keyboard submission',
    (tester) async {
      final response = Completer<http.Response>();
      fixture.respond = (_) => response.future;
      await start(tester);
      await fill(tester);
      await tester.tap(getSubmit());
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(tester.widget<TextFormField>(getUsername()).enabled, isFalse);
      expect(tester.widget<TextFormField>(getPassword()).enabled, isFalse);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(fixture.requests, hasLength(1));
      response.complete(http.Response(jsonEncode(fixture.session()), 200));
      await tester.pumpAndSettle();
      expect(find.byType(AdminShell), findsOneWidget);
    },
  );

  for (final status in [204, 401]) {
    testWidgets('logout $status clears local session and returns to Login', (
      tester,
    ) async {
      fixture.persist();
      fixture.respond = (_) async => http.Response('', status);
      await start(tester);
      await tester.tap(find.byTooltip('Log out'));
      await tester.pumpAndSettle();
      expectLogin();
      expect(fixture.storage.value, isNull);
      expect(fixture.requests.single.url.path, '/api/auth/logout');
      expect(
        fixture.requests.single.headers['Authorization'],
        'Bearer fixture-access-token',
      );
      // A second login must get a fresh, empty form.
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: getPassword(),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        isEmpty,
      );
    });
  }

  testWidgets(
    'failed logout keeps authenticated root and gives safe feedback',
    (tester) async {
      fixture.persist();
      fixture.respond = (_) async => http.Response('PRIVATE detail', 500);
      await start(tester);
      await tester.tap(find.byTooltip('Log out'));
      await tester.pumpAndSettle();
      expect(find.byType(AdminShell), findsOneWidget);
      expect(find.text('Unable to log out. Please try again.'), findsOneWidget);
      expect(find.textContaining('PRIVATE'), findsNothing);
      expect(fixture.storage.value, isNotNull);
    },
  );
  for (final role in ['Member', 'Trainer', 'Admin', 'Unknown']) {
    testWidgets('$role login selects only its supported platform root', (
      tester,
    ) async {
      fixture.respond = (_) async =>
          http.Response(jsonEncode(fixture.session(role: role)), 200);
      await start(tester);
      await fill(tester);
      await tester.tap(getSubmit());
      await tester.pumpAndSettle();
      expectRoleRoot(role);
      expect(getUsername(), findsNothing);
      expect(fixture.requests.single.url.path, '/api/auth/login');
      expect(jsonDecode(fixture.storage.value!)['role'], role);
    });
  }

  for (final role in ['Member', 'Trainer', 'Unknown']) {
    for (final status in [204, 401]) {
      testWidgets(
        'unsupported $role can sign out on $status without entering business UI',
        (tester) async {
          fixture.persist(role: role);
          final before = fixture.storage.value;
          fixture.respond = (_) async => http.Response('', status);
          await start(tester);
          expectRoleRoot(role);
          expect(fixture.requests, isEmpty);
          expect(fixture.storage.value, before);
          await tester.tap(find.text('Sign out'));
          await tester.pumpAndSettle();
          expectLogin();
          expect(fixture.storage.value, isNull);
          expect(fixture.requests.single.url.path, '/api/auth/logout');
          expect(
            fixture.requests.single.headers['Authorization'],
            'Bearer fixture-access-token',
          );
        },
      );
    }
  }
}
