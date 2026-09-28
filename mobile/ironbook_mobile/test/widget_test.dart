import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ironbook_mobile/main.dart';

void main() {
  testWidgets('shows center selection shell', (WidgetTester tester) async {
    await tester.pumpWidget(const IronBookMobileApp());

    expect(find.text('Choose Your Center'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
