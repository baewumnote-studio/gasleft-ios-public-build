import 'package:flutter_test/flutter_test.dart';
import 'package:gasleft/core/app_strings.dart';
import 'package:gasleft/core/enums.dart';

void main() {
  const strings = AppStrings.english;

  test('English catalog resolves placeholders', () {
    expect(
      strings.text('notificationRecheckTitle', {'name': 'BBQ Tank'}),
      'Time to recheck BBQ Tank',
    );
    expect(
      strings.text('notificationRecheckBody', {'days': 14}),
      'It’s been 14 days since your last weight check. Add a new reading for an updated estimate.',
    );
  });

  test('use cases resolve through the localization catalog', () {
    expect(strings.useCaseLabel(CylinderUseCase.bbq), 'BBQ / Grill');
    expect(strings.useCaseLabel(CylinderUseCase.rvCaravan), 'RV / Caravan');
    expect(strings.useCaseLabel(CylinderUseCase.other), 'Other');
  });

  test('catalog contains every core safety and notification string', () {
    for (final key in <String>[
      'planningEstimateShort',
      'tareHelpWc',
      'weightEstimateDisclaimer',
      'safetyBoundaryBody',
      'notificationRecheckTitle',
      'notificationRecheckBody',
    ]) {
      expect(AppStrings.englishCatalog[key], isNotNull, reason: key);
      expect(AppStrings.englishCatalog[key], isNotEmpty, reason: key);
    }
  });
}
