import '../../core/enums.dart';
import '../models/view_models.dart';
import 'mass_converter.dart';

abstract final class ReadingValidationService {
  static const int maxPortableMassGrams = 500000;

  static ReadingValidationResult validate({
    required int tareGrams,
    required int capacityGrams,
    required int currentTotalGrams,
    required MassUnit inputUnit,
  }) {
    if (tareGrams <= 0 || capacityGrams <= 0) {
      return const ReadingValidationResult(
        canSave: false,
        flag: ReadingValidationFlag.normal,
        messageKey: 'validationSpecsPositive',
      );
    }
    if (currentTotalGrams <= 0 || currentTotalGrams > maxPortableMassGrams) {
      return const ReadingValidationResult(
        canSave: false,
        flag: ReadingValidationFlag.normal,
        messageKey: 'validationPortableWeight',
      );
    }

    final tolerance = MassConverter.toleranceGrams(inputUnit);

    if (currentTotalGrams < tareGrams - tolerance) {
      return const ReadingValidationResult(
        canSave: false,
        flag: ReadingValidationFlag.normal,
        messageKey: 'validationBelowTare',
      );
    }
    if (currentTotalGrams < tareGrams) {
      return const ReadingValidationResult(
        canSave: true,
        flag: ReadingValidationFlag.nearTare,
        messageKey: 'validationNearTare',
      );
    }

    final nominalFull = tareGrams + capacityGrams;
    if (currentTotalGrams > nominalFull + tolerance) {
      return const ReadingValidationResult(
        canSave: true,
        flag: ReadingValidationFlag.aboveNominalFull,
        messageKey: 'validationAboveNominalFull',
        requiresExplicitConfirmation: true,
      );
    }

    return const ReadingValidationResult(
      canSave: true,
      flag: ReadingValidationFlag.normal,
    );
  }

  static bool looksLikeRefill({
    required int previousTotalGrams,
    required int newTotalGrams,
    required int capacityGrams,
    required MassUnit unit,
  }) {
    final noise = [
      MassConverter.toleranceGrams(unit),
      (capacityGrams * 0.01).round(),
    ].reduce((a, b) => a > b ? a : b);
    return newTotalGrams > previousTotalGrams + noise;
  }

  static CylinderStatus status({
    required double displayPercent,
    required double lowThresholdPct,
    required ReadingValidationFlag flag,
  }) {
    if (flag == ReadingValidationFlag.aboveNominalFull) {
      return CylinderStatus.checkInput;
    }
    if (displayPercent <= 10) return CylinderStatus.veryLow;
    if (displayPercent <= lowThresholdPct) return CylinderStatus.low;
    return CylinderStatus.good;
  }
}
