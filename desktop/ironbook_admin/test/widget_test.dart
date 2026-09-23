import 'package:flutter_test/flutter_test.dart';

import 'package:ironbook_admin/main.dart';

void main() {
  testWidgets('shows admin foundation screen', (WidgetTester tester) async {
    await tester.pumpWidget(const IronBookAdminApp());

    expect(find.text('IronBook Admin'), findsOneWidget);
    expect(find.text('Admin desktop app'), findsOneWidget);
  });
}
