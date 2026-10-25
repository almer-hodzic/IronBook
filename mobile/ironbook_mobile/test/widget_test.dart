import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_fixture.dart';

void main() {
  testWidgets('starts with session restoration before showing Login', (
    tester,
  ) async {
    final fixture = AuthFixture();
    await tester.pumpWidget(fixture.app());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Username'), findsOneWidget);
    expect(fixture.requests, isEmpty);
  });
}
