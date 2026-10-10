import 'package:flutter_test/flutter_test.dart';
import 'package:gasleft/core/enums.dart';
import 'package:gasleft/domain/models/cylinder.dart';
import 'package:gasleft/domain/models/settings_models.dart';
import 'package:gasleft/domain/models/view_models.dart';
import 'package:gasleft/domain/models/weight_reading.dart';

void main() {
  test('Cylinder map round trip preserves values', () {
    const original = Cylinder(
      id: 'c1',
      name: 'Camper',
      useCase: CylinderUseCase.rvCaravan,
      preferredUnit: MassUnit.lb,
      tareGrams: 7802,
      capacityGrams: 9072,
      lowThresholdPct: 25,
      currentRevision: 3,
      sortOrder: 2,
      createdAtEpochMs: 10,
      updatedAtEpochMs: 20,
    );
    final copy = Cylinder.fromMap(original.toMap());
    expect(copy.id, original.id);
    expect(copy.useCase, original.useCase);
    expect(copy.preferredUnit, original.preferredUnit);
    expect(copy.tareGrams, original.tareGrams);
    expect(copy.currentRevision, 3);
  });

  test('WeightReading map round trip preserves snapshots and event', () {
    const original = WeightReading(
      id: 'r1',
      cylinderId: 'c1',
      measuredAtEpochMs: 100,
      totalWeightGrams: 12746,
      tareGramsSnapshot: 7802,
      capacityGramsSnapshot: 9072,
      cylinderRevision: 3,
      eventType: ReadingEventType.replacement,
      validationFlag: ReadingValidationFlag.aboveNominalFull,
      isExcludedFromPrediction: true,
      predictionExclusionReason: PredictionExclusionReason.validation,
      note: 'check',
      createdAtEpochMs: 100,
      updatedAtEpochMs: 101,
    );
    final copy = WeightReading.fromMap(original.toMap());
    expect(copy.tareGramsSnapshot, 7802);
    expect(copy.capacityGramsSnapshot, 9072);
    expect(copy.eventType, ReadingEventType.replacement);
    expect(copy.validationFlag, ReadingValidationFlag.aboveNominalFull);
    expect(copy.isExcludedFromPrediction, isTrue);
    expect(
      copy.predictionExclusionReason,
      PredictionExclusionReason.validation,
    );
  });

  test('ReminderSettings map round trip preserves scheduling fields', () {
    const original = ReminderSettings(
      cylinderId: 'c1',
      recheckEnabled: true,
      recheckDays: 14,
      notificationId: 123,
      updatedAtEpochMs: 456,
    );
    final copy = ReminderSettings.fromMap(original.toMap());
    expect(copy.recheckEnabled, isTrue);
    expect(copy.recheckDays, 14);
    expect(copy.notificationId, 123);
  });

  test('CylinderSummary detects replacement awaiting its first reading', () {
    const cylinder = Cylinder(
      id: 'c1',
      name: 'BBQ',
      useCase: CylinderUseCase.bbq,
      preferredUnit: MassUnit.kg,
      tareGrams: 10000,
      capacityGrams: 9000,
      lowThresholdPct: 20,
      currentRevision: 2,
      sortOrder: 0,
      createdAtEpochMs: 1,
      updatedAtEpochMs: 2,
    );
    const oldReading = WeightReading(
      id: 'r1',
      cylinderId: 'c1',
      measuredAtEpochMs: 10,
      totalWeightGrams: 15000,
      tareGramsSnapshot: 10000,
      capacityGramsSnapshot: 9000,
      cylinderRevision: 1,
      eventType: ReadingEventType.normal,
      validationFlag: ReadingValidationFlag.normal,
      isExcludedFromPrediction: false,
      createdAtEpochMs: 10,
      updatedAtEpochMs: 10,
    );
    const summary = CylinderSummary(
      cylinder: cylinder,
      status: CylinderStatus.noReading,
      latestReading: oldReading,
    );
    expect(summary.awaitingReplacementReading, isTrue);
  });
}
