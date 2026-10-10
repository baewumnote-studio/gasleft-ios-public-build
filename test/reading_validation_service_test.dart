import 'package:flutter_test/flutter_test.dart';
import 'package:gasleft/core/enums.dart';
import 'package:gasleft/domain/services/reading_validation_service.dart';

void main() {
  group('ReadingValidationService', () {
    test('below tare beyond tolerance is blocked', () {
      final result = ReadingValidationService.validate(
        tareGrams: 10000,
        capacityGrams: 9000,
        currentTotalGrams: 9900,
        inputUnit: MassUnit.kg,
      );
      expect(result.canSave, isFalse);
    });

    test('near tare is accepted as nearTare', () {
      final result = ReadingValidationService.validate(
        tareGrams: 10000,
        capacityGrams: 9000,
        currentTotalGrams: 9970,
        inputUnit: MassUnit.kg,
      );
      expect(result.canSave, isTrue);
      expect(result.flag, ReadingValidationFlag.nearTare);
    });

    test('material overfull requires explicit confirmation', () {
      final result = ReadingValidationService.validate(
        tareGrams: 10000,
        capacityGrams: 9000,
        currentTotalGrams: 19100,
        inputUnit: MassUnit.kg,
      );
      expect(result.canSave, isTrue);
      expect(result.flag, ReadingValidationFlag.aboveNominalFull);
      expect(result.requiresExplicitConfirmation, isTrue);
    });

    test('status boundaries', () {
      expect(
        ReadingValidationService.status(
          displayPercent: 50,
          lowThresholdPct: 20,
          flag: ReadingValidationFlag.normal,
        ),
        CylinderStatus.good,
      );
      expect(
        ReadingValidationService.status(
          displayPercent: 20,
          lowThresholdPct: 20,
          flag: ReadingValidationFlag.normal,
        ),
        CylinderStatus.low,
      );
      expect(
        ReadingValidationService.status(
          displayPercent: 10,
          lowThresholdPct: 20,
          flag: ReadingValidationFlag.normal,
        ),
        CylinderStatus.veryLow,
      );
    });

    test('exact tare is valid and not near-tare', () {
      final result = ReadingValidationService.validate(
        tareGrams: 10000,
        capacityGrams: 9000,
        currentTotalGrams: 10000,
        inputUnit: MassUnit.kg,
      );
      expect(result.canSave, isTrue);
      expect(result.flag, ReadingValidationFlag.normal);
    });

    test('within full-weight tolerance is not flagged overfull', () {
      final result = ReadingValidationService.validate(
        tareGrams: 10000,
        capacityGrams: 9000,
        currentTotalGrams: 19040,
        inputUnit: MassUnit.kg,
      );
      expect(result.canSave, isTrue);
      expect(result.flag, ReadingValidationFlag.normal);
    });

    test('portable sanity maximum is enforced', () {
      final result = ReadingValidationService.validate(
        tareGrams: 10000,
        capacityGrams: 9000,
        currentTotalGrams: 500001,
        inputUnit: MassUnit.kg,
      );
      expect(result.canSave, isFalse);
    });

    test('refill detection ignores noise but flags meaningful increase', () {
      expect(
        ReadingValidationService.looksLikeRefill(
          previousTotalGrams: 15000,
          newTotalGrams: 15080,
          capacityGrams: 9000,
          unit: MassUnit.kg,
        ),
        isFalse,
      );
      expect(
        ReadingValidationService.looksLikeRefill(
          previousTotalGrams: 15000,
          newTotalGrams: 15100,
          capacityGrams: 9000,
          unit: MassUnit.kg,
        ),
        isTrue,
      );
    });

    test('check-input flag overrides percentage status', () {
      expect(
        ReadingValidationService.status(
          displayPercent: 100,
          lowThresholdPct: 20,
          flag: ReadingValidationFlag.aboveNominalFull,
        ),
        CylinderStatus.checkInput,
      );
    });
  });
}
