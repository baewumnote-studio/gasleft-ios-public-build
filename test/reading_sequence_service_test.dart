import 'package:flutter_test/flutter_test.dart';
import 'package:gasleft/core/enums.dart';
import 'package:gasleft/domain/models/cylinder.dart';
import 'package:gasleft/domain/models/view_models.dart';
import 'package:gasleft/domain/models/weight_reading.dart';
import 'package:gasleft/domain/services/reading_sequence_service.dart';

Cylinder cylinder({int revision = 2, int tare = 10000, int capacity = 9000}) {
  return Cylinder(
    id: 'c1',
    name: 'BBQ',
    useCase: CylinderUseCase.bbq,
    preferredUnit: MassUnit.kg,
    tareGrams: tare,
    capacityGrams: capacity,
    lowThresholdPct: 20,
    currentRevision: revision,
    sortOrder: 0,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
  );
}

WeightReading reading({
  int revision = 1,
  int tare = 10000,
  int capacity = 9000,
  int total = 15000,
}) {
  return WeightReading(
    id: 'r1',
    cylinderId: 'c1',
    measuredAtEpochMs: 1,
    totalWeightGrams: total,
    tareGramsSnapshot: tare,
    capacityGramsSnapshot: capacity,
    cylinderRevision: revision,
    eventType: ReadingEventType.normal,
    validationFlag: ReadingValidationFlag.normal,
    isExcludedFromPrediction: false,
    createdAtEpochMs: 1,
    updatedAtEpochMs: 1,
  );
}

const current = GasCalculation(
  rawRemainingGrams: 4000,
  displayRemainingGrams: 4000,
  rawPercent: 44.444,
  displayPercent: 44.444,
);

void main() {
  group('ReadingSequenceService', () {
    test(
      'empty current revision after replacement marks next reading as replacement',
      () {
        expect(
          ReadingSequenceService.startsNewRevision(
            cylinder: cylinder(revision: 2),
            latest: null,
          ),
          isTrue,
        );
      },
    );

    test('empty first revision is a normal first reading', () {
      expect(
        ReadingSequenceService.startsNewRevision(
          cylinder: cylinder(revision: 1),
          latest: null,
        ),
        isFalse,
      );
    });

    test('revision mismatch means next reading marks replacement', () {
      expect(
        ReadingSequenceService.startsNewRevision(
          cylinder: cylinder(revision: 2),
          latest: reading(revision: 1),
        ),
        isTrue,
      );
    });

    test('same revision does not start replacement', () {
      expect(
        ReadingSequenceService.startsNewRevision(
          cylinder: cylinder(revision: 2),
          latest: reading(revision: 2),
        ),
        isFalse,
      );
    });

    test('consumption delta only compares compatible normal readings', () {
      expect(
        ReadingSequenceService.consumedSincePrevious(
          cylinder: cylinder(revision: 2),
          previous: reading(revision: 2, total: 15000),
          current: current,
          currentEventType: ReadingEventType.normal,
          currentValidationFlag: ReadingValidationFlag.normal,
        ),
        1000,
      );
    });

    test('tare correction prevents misleading cross-spec delta', () {
      expect(
        ReadingSequenceService.consumedSincePrevious(
          cylinder: cylinder(revision: 2, tare: 10500),
          previous: reading(revision: 2, tare: 10000, total: 15000),
          current: current,
          currentEventType: ReadingEventType.normal,
          currentValidationFlag: ReadingValidationFlag.normal,
        ),
        isNull,
      );
    });

    test('replacement reading never shows consumption delta', () {
      expect(
        ReadingSequenceService.consumedSincePrevious(
          cylinder: cylinder(revision: 2),
          previous: reading(revision: 2, total: 15000),
          current: current,
          currentEventType: ReadingEventType.replacement,
          currentValidationFlag: ReadingValidationFlag.normal,
        ),
        isNull,
      );
    });

    test('does not show consumption across suspicious overfull readings', () {
      final invalidPrevious = reading(
        revision: 2,
      ).copyWith(validationFlag: ReadingValidationFlag.aboveNominalFull);
      final result = ReadingSequenceService.consumedSincePrevious(
        cylinder: cylinder(),
        previous: invalidPrevious,
        current: const GasCalculation(
          rawRemainingGrams: 4000,
          displayRemainingGrams: 4000,
          rawPercent: 40,
          displayPercent: 40,
        ),
        currentEventType: ReadingEventType.normal,
        currentValidationFlag: ReadingValidationFlag.normal,
      );
      expect(result, isNull);
    });

    test('does not show consumption when current reading is overfull', () {
      final result = ReadingSequenceService.consumedSincePrevious(
        cylinder: cylinder(revision: 2),
        previous: reading(revision: 2, total: 15000),
        current: current,
        currentEventType: ReadingEventType.normal,
        currentValidationFlag: ReadingValidationFlag.aboveNominalFull,
      );
      expect(result, isNull);
    });
  });
}
