import '../models/cylinder.dart';
import '../models/view_models.dart';
import '../models/weight_reading.dart';
import '../../core/enums.dart';

/// Pure rules about how consecutive readings relate to a physical-cylinder
/// revision. Kept outside widgets so replacement/history behavior is testable.
abstract final class ReadingSequenceService {
  static bool startsNewRevision({
    required Cylinder cylinder,
    required WeightReading? latest,
  }) {
    if (latest == null) return cylinder.currentRevision > 1;
    return latest.cylinderRevision != cylinder.currentRevision;
  }

  static int? consumedSincePrevious({
    required Cylinder cylinder,
    required WeightReading? previous,
    required GasCalculation current,
    required ReadingEventType currentEventType,
    required ReadingValidationFlag currentValidationFlag,
  }) {
    if (previous == null ||
        currentEventType != ReadingEventType.normal ||
        currentValidationFlag == ReadingValidationFlag.aboveNominalFull ||
        previous.validationFlag == ReadingValidationFlag.aboveNominalFull ||
        previous.cylinderRevision != cylinder.currentRevision ||
        previous.tareGramsSnapshot != cylinder.tareGrams) {
      return null;
    }

    final previousRemaining =
        (previous.totalWeightGrams - previous.tareGramsSnapshot)
            .clamp(0, previous.capacityGramsSnapshot)
            .toInt();
    final consumed = previousRemaining - current.displayRemainingGrams;
    return consumed > 0 ? consumed : null;
  }
}
