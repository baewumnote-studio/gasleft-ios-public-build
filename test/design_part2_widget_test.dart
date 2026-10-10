import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gasleft/core/app_strings.dart';
import 'package:gasleft/core/enums.dart';
import 'package:gasleft/core/theme/app_theme.dart';
import 'package:gasleft/domain/models/cylinder.dart';
import 'package:gasleft/domain/models/view_models.dart';
import 'package:gasleft/features/add_reading/reading_result_screen.dart';

void main() {
  testWidgets(
    'reading result stays usable on a small iPhone at 200% text scale',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const cylinder = Cylinder(
        id: 'c1',
        name: 'BBQ Tank',
        useCase: CylinderUseCase.bbq,
        preferredUnit: MassUnit.kg,
        tareGrams: 10400,
        capacityGrams: 9000,
        lowThresholdPct: 50,
        currentRevision: 1,
        sortOrder: 0,
        createdAtEpochMs: 1,
        updatedAtEpochMs: 1,
      );

      const args = ReadingResultArgs(
        cylinder: cylinder,
        calculation: GasCalculation(
          rawRemainingGrams: 4400,
          displayRemainingGrams: 4400,
          rawPercent: 48.888,
          displayPercent: 48.9,
        ),
        status: CylinderStatus.low,
        validationFlag: ReadingValidationFlag.normal,
        deltaGrams: 600,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: const [AppStrings.delegate],
            supportedLocales: AppStrings.supportedLocales,
            builder: (context, child) {
              final media = MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2));
              return MediaQuery(data: media, child: child!);
            },
            home: const ReadingResultScreen(args: args),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Reading saved'), findsOneWidget);
      expect(find.text('49%'), findsOneWidget);
      expect(find.text('BBQ Tank'), findsOneWidget);
      expect(find.textContaining('Low'), findsWidgets);
      await tester.scrollUntilVisible(find.textContaining('Used'), 150);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Used'), findsOneWidget);
    },
  );
}
