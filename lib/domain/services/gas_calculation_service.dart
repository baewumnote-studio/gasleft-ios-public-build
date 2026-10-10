import '../models/view_models.dart';

abstract final class GasCalculationService {
  static GasCalculation calculate({
    required int tareGrams,
    required int capacityGrams,
    required int currentTotalGrams,
  }) {
    if (tareGrams <= 0 || capacityGrams <= 0 || currentTotalGrams <= 0) {
      throw ArgumentError('Weights and capacity must be positive.');
    }

    final rawRemaining = currentTotalGrams - tareGrams;
    final rawPercent = rawRemaining / capacityGrams * 100.0;

    return GasCalculation(
      rawRemainingGrams: rawRemaining,
      displayRemainingGrams: rawRemaining.clamp(0, capacityGrams).toInt(),
      rawPercent: rawPercent,
      displayPercent: rawPercent.clamp(0.0, 100.0).toDouble(),
    );
  }
}
