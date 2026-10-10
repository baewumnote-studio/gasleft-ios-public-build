import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gasleft/core/enums.dart';
import 'package:gasleft/shared/status_ui.dart';

void main() {
  testWidgets('status badge exposes text semantics and not color alone', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StatusBadge(status: CylinderStatus.low)),
      ),
    );

    expect(find.text('Low'), findsOneWidget);
    expect(find.bySemanticsLabel('Status: Low'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets('dark mode uses a distinct high-visibility good status color', (
    tester,
  ) async {
    late Color lightColor;
    late Color darkColor;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Builder(
          builder: (context) {
            lightColor = StatusUi.resolve(context, CylinderStatus.good).color;
            return const SizedBox();
          },
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) {
            darkColor = StatusUi.resolve(context, CylinderStatus.good).color;
            return const SizedBox();
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(darkColor, isNot(lightColor));
  });
}
