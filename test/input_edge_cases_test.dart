import 'package:flutter_test/flutter_test.dart';

import 'package:gasleft/core/enums.dart';
import 'package:gasleft/core/formatters.dart';
import 'package:gasleft/domain/services/mass_converter.dart';
import 'package:gasleft/domain/services/reading_validation_service.dart';

void main() {
  group('decimal parsing', () {
    test('accepts dot and comma decimal separators', () {
      expect(AppFormatters.parseDecimal('14.8'), 14.8);
      expect(AppFormatters.parseDecimal('14,8'), 14.8);
    });

    test('rejects malformed values', () {
      expect(AppFormatters.parseDecimal('14,8.2'), isNull);
      expect(AppFormatters.parseDecimal('abc'), isNull);
      expect(AppFormatters.parseDecimal(''), isNull);
    });
  });

  group('portable-cylinder guard rails', () {
    test('500kg exactly is accepted by the upper-bound guard', () {
      final result = ReadingValidationService.validate(
        tareGrams: 10000,
        capacityGrams: 490000,
        currentTotalGrams: 500000,
        inputUnit: MassUnit.kg,
      );
      expect(result.canSave, isTrue);
    });

    test('above 500kg is rejected', () {
      final result = ReadingValidationService.validate(
        tareGrams: 10000,
        capacityGrams: 500000,
        currentTotalGrams: 500001,
        inputUnit: MassUnit.kg,
      );
      expect(result.canSave, isFalse);
    });

    test('pound tolerance rounds from exact conversion constant', () {
      expect(
        MassConverter.toleranceGrams(MassUnit.lb),
        (0.1 * MassConverter.gramsPerPound).round(),
      );
    });
  });
}
