import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:galarm_enhanced/presentation/screens/alarm_editor_screen.dart';

void main() {
  testWidgets('AlarmEditorScreen validates empty title and shows core controls',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AlarmEditorScreen(),
        ),
      ),
    );

    expect(find.text('New Alarm'), findsOneWidget);
    expect(find.text('Ring even on Vibrate / Silent'), findsOneWidget);

    await tester.tap(find.text('Save Alarm'));
    await tester.pumpAndSettle();

    expect(find.text('Title is required'), findsOneWidget);
  });
}
