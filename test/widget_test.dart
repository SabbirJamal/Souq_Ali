import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:souqali/seller_login_page.dart';

void main() {
  testWidgets('shows seller login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SellerLoginPage()));

    expect(find.text('Seller Login'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('New seller? Register'), findsOneWidget);
  });
}
