import 'reading_validation_service.dart';

class CylinderSpecValidationResult {
  const CylinderSpecValidationResult({required this.isValid, this.messageKey});

  final bool isValid;
  final String? messageKey;
}

abstract final class CylinderSpecValidationService {
  static CylinderSpecValidationResult validate({
    required int tareGrams,
    required int capacityGrams,
  }) {
    if (tareGrams <= 0 || capacityGrams <= 0) {
      return const CylinderSpecValidationResult(
        isValid: false,
        messageKey: 'validationSpecsPositive',
      );
    }
    if (tareGrams > ReadingValidationService.maxPortableMassGrams ||
        capacityGrams > ReadingValidationService.maxPortableMassGrams) {
      return const CylinderSpecValidationResult(
        isValid: false,
        messageKey: 'checkUnitValue',
      );
    }
    if (tareGrams + capacityGrams >
        ReadingValidationService.maxPortableMassGrams) {
      return const CylinderSpecValidationResult(
        isValid: false,
        messageKey: 'validationPortableFullMass',
      );
    }
    return const CylinderSpecValidationResult(isValid: true);
  }
}
