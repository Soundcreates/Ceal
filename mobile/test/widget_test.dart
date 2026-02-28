import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('basic widget smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('AfterMath'),
        ),
      ),
    );
    expect(find.text('AfterMath'), findsOneWidget);
  });
}
