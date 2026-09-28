import 'package:flutter_test/flutter_test.dart';

import 'package:ironbook_admin/main.dart';

void main() {
  testWidgets('shows admin centers shell', (WidgetTester tester) async {
    await tester.pumpWidget(const IronBookAdminApp());

    expect(find.text('IronBook'), findsOneWidget);
    expect(find.text('Centers Management'), findsOneWidget);
  });
}
