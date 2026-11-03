// Basic smoke test — confirms SelmsApp builds and the login screen renders
// its core elements (SELMS wordmark, role tabs, sign-in button).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:selms/main.dart';

void main() {
  testWidgets('SELMS login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const SelmsApp());

    expect(find.text('SELMS'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('HR Staff'), findsOneWidget);
    expect(find.text('IT Staff'), findsOneWidget);
    expect(find.text('Employee'), findsOneWidget);
  });
}
