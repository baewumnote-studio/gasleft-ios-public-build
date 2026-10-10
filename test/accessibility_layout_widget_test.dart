import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gasleft/core/app_strings.dart';
import 'package:gasleft/features/onboarding/onboarding_screen.dart';

void main() {
  testWidgets(
    'onboarding supports a small iPhone viewport at 200% text scale',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            supportedLocales: AppStrings.supportedLocales,
            builder: (context, child) {
              final media = MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2));
              return MediaQuery(data: media, child: child!);
            },
            home: const OnboardingScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.bySemanticsLabel('Page 1 of 3'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-280, 0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Page 2 of 3'), findsOneWidget);
      expect(find.text('Where do I find it?'), findsOneWidget);
    },
  );
}
