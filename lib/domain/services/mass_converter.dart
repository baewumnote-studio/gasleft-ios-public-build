import '../../core/enums.dart';

abstract final class MassConverter {
  static const double gramsPerKilogram = 1000.0;
  static const double gramsPerPound = 453.59237;

  static int toGrams(double value, MassUnit unit) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(value, 'value', 'Must be finite and >= 0');
    }
    final grams = switch (unit) {
      MassUnit.kg => value * gramsPerKilogram,
      MassUnit.lb => value * gramsPerPound,
    };
    return grams.round();
  }

  static double fromGrams(int grams, MassUnit unit) {
    return switch (unit) {
      MassUnit.kg => grams / gramsPerKilogram,
      MassUnit.lb => grams / gramsPerPound,
    };
  }

  static int toleranceGrams(MassUnit unit) => switch (unit) {
    MassUnit.kg => 50,
    MassUnit.lb => (0.1 * gramsPerPound).round(),
  };
}
