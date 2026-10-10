import '../../core/enums.dart';

class WeightReading {
  const WeightReading({
    required this.id,
    required this.cylinderId,
    required this.measuredAtEpochMs,
    required this.totalWeightGrams,
    required this.tareGramsSnapshot,
    required this.capacityGramsSnapshot,
    required this.cylinderRevision,
    required this.eventType,
    required this.validationFlag,
    required this.isExcludedFromPrediction,
    required this.createdAtEpochMs,
    required this.updatedAtEpochMs,
    this.predictionExclusionReason = PredictionExclusionReason.none,
    this.note,
  });

  final String id;
  final String cylinderId;
  final int measuredAtEpochMs;
  final int totalWeightGrams;
  final int tareGramsSnapshot;
  final int capacityGramsSnapshot;
  final int cylinderRevision;
  final ReadingEventType eventType;
  final ReadingValidationFlag validationFlag;
  final bool isExcludedFromPrediction;
  final PredictionExclusionReason predictionExclusionReason;
  final String? note;
  final int createdAtEpochMs;
  final int updatedAtEpochMs;

  static PredictionExclusionReason _reasonFromMap(Map<String, Object?> map) {
    final stored = map['prediction_exclusion_reason'] as String?;
    if (stored != null) return PredictionExclusionReason.fromDb(stored);
    final excluded = (map['excluded_from_prediction'] as int? ?? 0) == 1;
    if (!excluded) return PredictionExclusionReason.none;
    if (map['validation_flag'] == ReadingValidationFlag.aboveNominalFull.name) {
      return PredictionExclusionReason.validation;
    }
    // Legacy rows did not distinguish sequence-derived exclusions from
    // explicit/manual ones. Database migration reconstructs sequence reasons;
    // this fallback is intentionally conservative for ad-hoc maps/tests.
    return PredictionExclusionReason.manual;
  }

  factory WeightReading.fromMap(Map<String, Object?> map) {
    return WeightReading(
      id: map['id']! as String,
      cylinderId: map['cylinder_id']! as String,
      measuredAtEpochMs: map['measured_at_ms']! as int,
      totalWeightGrams: map['total_weight_grams']! as int,
      tareGramsSnapshot: map['tare_grams_snapshot']! as int,
      capacityGramsSnapshot: map['capacity_grams_snapshot']! as int,
      cylinderRevision: map['cylinder_revision']! as int,
      eventType: ReadingEventType.fromDb(map['event_type']! as String),
      validationFlag: ReadingValidationFlag.fromDb(
        map['validation_flag']! as String,
      ),
      isExcludedFromPrediction: (map['excluded_from_prediction']! as int) == 1,
      predictionExclusionReason: _reasonFromMap(map),
      note: map['note'] as String?,
      createdAtEpochMs: map['created_at_ms']! as int,
      updatedAtEpochMs: map['updated_at_ms']! as int,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'cylinder_id': cylinderId,
    'measured_at_ms': measuredAtEpochMs,
    'total_weight_grams': totalWeightGrams,
    'tare_grams_snapshot': tareGramsSnapshot,
    'capacity_grams_snapshot': capacityGramsSnapshot,
    'cylinder_revision': cylinderRevision,
    'event_type': eventType.name,
    'validation_flag': validationFlag.name,
    'excluded_from_prediction': isExcludedFromPrediction ? 1 : 0,
    'prediction_exclusion_reason': predictionExclusionReason.name,
    'note': note,
    'created_at_ms': createdAtEpochMs,
    'updated_at_ms': updatedAtEpochMs,
  };

  WeightReading copyWith({
    int? measuredAtEpochMs,
    int? totalWeightGrams,
    ReadingEventType? eventType,
    ReadingValidationFlag? validationFlag,
    bool? isExcludedFromPrediction,
    PredictionExclusionReason? predictionExclusionReason,
    int? updatedAtEpochMs,
  }) {
    final nextReason =
        predictionExclusionReason ?? this.predictionExclusionReason;
    final nextExcluded =
        isExcludedFromPrediction ??
        (predictionExclusionReason == null
            ? this.isExcludedFromPrediction
            : nextReason != PredictionExclusionReason.none);
    return WeightReading(
      id: id,
      cylinderId: cylinderId,
      measuredAtEpochMs: measuredAtEpochMs ?? this.measuredAtEpochMs,
      totalWeightGrams: totalWeightGrams ?? this.totalWeightGrams,
      tareGramsSnapshot: tareGramsSnapshot,
      capacityGramsSnapshot: capacityGramsSnapshot,
      cylinderRevision: cylinderRevision,
      eventType: eventType ?? this.eventType,
      validationFlag: validationFlag ?? this.validationFlag,
      isExcludedFromPrediction: nextExcluded,
      predictionExclusionReason: nextReason,
      note: note,
      createdAtEpochMs: createdAtEpochMs,
      updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
    );
  }
}
