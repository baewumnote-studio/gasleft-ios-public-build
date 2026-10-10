import '../../core/enums.dart';
import 'cylinder.dart';
import 'settings_models.dart';
import 'weight_reading.dart';

class GasCalculation {
  const GasCalculation({
    required this.rawRemainingGrams,
    required this.displayRemainingGrams,
    required this.rawPercent,
    required this.displayPercent,
  });

  final int rawRemainingGrams;
  final int displayRemainingGrams;
  final double rawPercent;
  final double displayPercent;
}

class ReadingValidationResult {
  const ReadingValidationResult({
    required this.canSave,
    required this.flag,
    this.messageKey,
    this.requiresExplicitConfirmation = false,
  });

  final bool canSave;
  final ReadingValidationFlag flag;
  final String? messageKey;
  final bool requiresExplicitConfirmation;
}

class CylinderSummary {
  const CylinderSummary({
    required this.cylinder,
    required this.status,
    this.latestReading,
    this.calculation,
  });

  final Cylinder cylinder;
  final WeightReading? latestReading;
  final GasCalculation? calculation;
  final CylinderStatus status;

  bool get awaitingReplacementReading =>
      calculation == null && cylinder.currentRevision > 1;
}

class CylinderDetailData {
  const CylinderDetailData({
    required this.cylinder,
    required this.summary,
    required this.readings,
    required this.reminder,
  });

  final Cylinder cylinder;
  final CylinderSummary summary;
  final List<WeightReading> readings;
  final ReminderSettings reminder;
}
