import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('builds a basic widget tree', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('BIZ SOOQ'))),
    );

    expect(find.text('BIZ SOOQ'), findsOneWidget);
  });
}
