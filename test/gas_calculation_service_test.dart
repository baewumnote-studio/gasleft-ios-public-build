import 'package:flutter_test/flutter_test.dart';
import 'package:gasleft/domain/services/gas_calculation_service.dart';

void main() {
  group('GasCalculationService', () {
    test('10/10/15 gives 5 remaining and 50%', () {
      final result = GasCalculationService.calculate(
        tareGrams: 10000,
        capacityGrams: 10000,
        currentTotalGrams: 15000,
      );
      expect(result.displayRemainingGrams, 5000);
      expect(result.displayPercent, 50);
    });

    test('10.4kg tare, 9kg capacity, 14.8kg total gives 4.4kg', () {
      final result = GasCalculationService.calculate(
        tareGrams: 10400,
        capacityGrams: 9000,
        currentTotalGrams: 14800,
      );
      expect(result.displayRemainingGrams, 4400);
      expect(result.rawPercent, closeTo(48.888888, 0.0001));
    });

    test('over 100 preserves raw but caps display', () {
      final result = GasCalculationService.calculate(
        tareGrams: 10000,
        capacityGrams: 10000,
        currentTotalGrams: 21000,
      );
      expect(result.rawPercent, closeTo(110, 0.000000001));
      expect(result.displayPercent, 100);
      expect(result.rawRemainingGrams, 11000);
      expect(result.displayRemainingGrams, 10000);
    });

    test('below tare preserves raw negative but display is zero', () {
      final result = GasCalculationService.calculate(
        tareGrams: 10000,
        capacityGrams: 9000,
        currentTotalGrams: 9950,
      );
      expect(result.rawRemainingGrams, -50);
      expect(result.displayRemainingGrams, 0);
      expect(result.displayPercent, 0);
    });

    test('invalid zero capacity throws', () {
      expect(
        () => GasCalculationService.calculate(
          tareGrams: 10000,
          capacityGrams: 0,
          currentTotalGrams: 15000,
        ),
        throwsArgumentError,
      );
    });
  });
}
