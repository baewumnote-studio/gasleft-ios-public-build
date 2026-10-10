import 'package:flutter_test/flutter_test.dart';
import 'package:gasleft/domain/services/cylinder_spec_validation_service.dart';

void main() {
  test('accepts a normal portable cylinder', () {
    final result = CylinderSpecValidationService.validate(
      tareGrams: 10400,
      capacityGrams: 9000,
    );
    expect(result.isValid, isTrue);
  });

  test('rejects non-positive specs', () {
    final result = CylinderSpecValidationService.validate(
      tareGrams: 0,
      capacityGrams: 9000,
    );
    expect(result.isValid, isFalse);
  });

  test('rejects theoretical full mass outside portable scope', () {
    final result = CylinderSpecValidationService.validate(
      tareGrams: 300000,
      capacityGrams: 250000,
    );
    expect(result.isValid, isFalse);
    expect(result.messageKey, 'validationPortableFullMass');
  });
}
