import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gasleft/core/enums.dart';
import 'package:gasleft/data/app_database.dart';
import 'package:gasleft/data/gas_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase database;
  late GasRepository repository;

  setUp(() {
    database = AppDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePathOverride: inMemoryDatabasePath,
    );
    repository = GasRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<String> seedCylinder() {
    return repository.createCylinder(
      name: 'BBQ',
      useCase: CylinderUseCase.bbq,
      preferredUnit: MassUnit.kg,
      tareGrams: 10000,
      capacityGrams: 10000,
      lowThresholdPct: 20,
    );
  }

  test('correcting specs rewrites snapshots in the current revision', () async {
    final id = await seedCylinder();
    final cylinder = (await repository.getCylinder(id))!;
    await repository.addReading(
      cylinder: cylinder,
      measuredAtEpochMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
      totalWeightGrams: 15000,
      eventType: ReadingEventType.normal,
      validationFlag: ReadingValidationFlag.normal,
      excludedFromPrediction: false,
    );

    final updatedIdentity = cylinder.copyWith(name: 'BBQ corrected');
    await repository.correctCylinderSpecs(
      cylinder: updatedIdentity,
      newTareGrams: 11000,
      newCapacityGrams: 9000,
      unit: MassUnit.kg,
    );

    final savedCylinder = (await repository.getCylinder(id))!;
    final reading = (await repository.getLatestReading(id))!;
    final summary = (await repository.getDetail(id))!.summary;

    expect(savedCylinder.name, 'BBQ corrected');
    expect(savedCylinder.currentRevision, 1);
    expect(savedCylinder.tareGrams, 11000);
    expect(savedCylinder.capacityGrams, 9000);
    expect(reading.tareGramsSnapshot, 11000);
    expect(reading.capacityGramsSnapshot, 9000);
    expect(summary.calculation!.displayRemainingGrams, 4000);
  });

  test(
    'spec correction clears exclusion caused only by an old overfull flag',
    () async {
      final id = await seedCylinder();
      final cylinder = (await repository.getCylinder(id))!;
      await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
        totalWeightGrams: 20500,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.aboveNominalFull,
        excludedFromPrediction: true,
      );

      await repository.correctCylinderSpecs(
        cylinder: cylinder,
        newTareGrams: 10000,
        newCapacityGrams: 11000,
        unit: MassUnit.kg,
      );

      final reading = (await repository.getLatestReading(id))!;
      expect(reading.validationFlag, ReadingValidationFlag.normal);
      expect(reading.isExcludedFromPrediction, isFalse);
    },
  );

  test('spec correction preserves a non-overfull/manual exclusion', () async {
    final id = await seedCylinder();
    final cylinder = (await repository.getCylinder(id))!;
    await repository.addReading(
      cylinder: cylinder,
      measuredAtEpochMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
      totalWeightGrams: 15000,
      eventType: ReadingEventType.normal,
      validationFlag: ReadingValidationFlag.normal,
      excludedFromPrediction: true,
    );

    await repository.correctCylinderSpecs(
      cylinder: cylinder,
      newTareGrams: 11000,
      newCapacityGrams: 9000,
      unit: MassUnit.kg,
    );

    final reading = (await repository.getLatestReading(id))!;
    expect(reading.validationFlag, ReadingValidationFlag.normal);
    expect(reading.isExcludedFromPrediction, isTrue);
    expect(reading.predictionExclusionReason, PredictionExclusionReason.manual);
  });

  test(
    'invalid correction rolls back cylinder and reading snapshots',
    () async {
      final id = await seedCylinder();
      final cylinder = (await repository.getCylinder(id))!;
      await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
        totalWeightGrams: 15000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );

      await expectLater(
        repository.correctCylinderSpecs(
          cylinder: cylinder,
          newTareGrams: 16000,
          newCapacityGrams: 10000,
          unit: MassUnit.kg,
        ),
        throwsA(isA<CylinderSpecCorrectionException>()),
      );

      final savedCylinder = (await repository.getCylinder(id))!;
      final reading = (await repository.getLatestReading(id))!;
      expect(savedCylinder.tareGrams, 10000);
      expect(savedCylinder.capacityGrams, 10000);
      expect(reading.tareGramsSnapshot, 10000);
      expect(reading.capacityGramsSnapshot, 10000);
    },
  );

  test(
    'physical replacement starts a revision without rewriting history',
    () async {
      final id = await seedCylinder();
      var cylinder = (await repository.getCylinder(id))!;
      await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
        totalWeightGrams: 15000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );

      await repository.replaceCylinder(
        cylinder: cylinder,
        newTareGrams: 8000,
        newCapacityGrams: 9000,
        unit: MassUnit.kg,
      );

      cylinder = (await repository.getCylinder(id))!;
      final oldReading = (await repository.getLatestReading(id))!;
      final detail = (await repository.getDetail(id))!;

      expect(cylinder.currentRevision, 2);
      expect(oldReading.cylinderRevision, 1);
      expect(oldReading.tareGramsSnapshot, 10000);
      expect(oldReading.capacityGramsSnapshot, 10000);
      expect(detail.summary.status, CylinderStatus.noReading);
      expect(detail.summary.awaitingReplacementReading, isTrue);
    },
  );

  test('deleting cylinder cascades readings and reminder row', () async {
    final id = await seedCylinder();
    final cylinder = (await repository.getCylinder(id))!;
    await repository.addReading(
      cylinder: cylinder,
      measuredAtEpochMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
      totalWeightGrams: 15000,
      eventType: ReadingEventType.normal,
      validationFlag: ReadingValidationFlag.normal,
      excludedFromPrediction: false,
    );

    await repository.deleteCylinder(id);

    expect(await repository.getCylinder(id), isNull);
    expect(await repository.listReadings(id), isEmpty);
    final db = await database.db;
    final reminderRows = await db.query(
      'reminder_settings',
      where: 'cylinder_id = ?',
      whereArgs: [id],
    );
    expect(reminderRows, isEmpty);
  });

  test('cylinders keep stable creation order', () async {
    final first = await repository.createCylinder(
      name: 'First',
      useCase: CylinderUseCase.bbq,
      preferredUnit: MassUnit.kg,
      tareGrams: 10000,
      capacityGrams: 9000,
      lowThresholdPct: 20,
    );
    final second = await repository.createCylinder(
      name: 'Second',
      useCase: CylinderUseCase.camping,
      preferredUnit: MassUnit.kg,
      tareGrams: 8000,
      capacityGrams: 5000,
      lowThresholdPct: 20,
    );

    final cylinders = await repository.listCylinders();
    expect(cylinders.map((e) => e.id), [first, second]);
    expect(cylinders.map((e) => e.sortOrder), [0, 1]);
  });

  test(
    'successful reading saves count completed actions and deletion does not undo the counter',
    () async {
      final id = await seedCylinder();
      final cylinder = (await repository.getCylinder(id))!;
      final readingId = await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
        totalWeightGrams: 15000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );

      expect((await repository.getAdState()).completedReadingCount, 1);
      await repository.deleteReading(readingId);
      expect((await repository.getAdState()).completedReadingCount, 1);
    },
  );

  test('markFirstSessionCompleted is idempotent', () async {
    expect((await repository.getAdState()).firstSessionCompleted, isFalse);
    await repository.markFirstSessionCompleted();
    await repository.markFirstSessionCompleted();
    expect((await repository.getAdState()).firstSessionCompleted, isTrue);
  });

  test(
    'current revision remains current even when its reading is back-dated',
    () async {
      final id = await seedCylinder();
      var cylinder = (await repository.getCylinder(id))!;
      await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 10).millisecondsSinceEpoch,
        totalWeightGrams: 15000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );

      await repository.replaceCylinder(
        cylinder: cylinder,
        newTareGrams: 8000,
        newCapacityGrams: 9000,
        unit: MassUnit.kg,
      );
      cylinder = (await repository.getCylinder(id))!;
      await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 5).millisecondsSinceEpoch,
        totalWeightGrams: 12000,
        eventType: ReadingEventType.replacement,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );

      final latestAny = (await repository.getLatestReading(id))!;
      final latestCurrent = (await repository.getLatestReadingForRevision(
        id,
        cylinder.currentRevision,
      ))!;
      final detail = (await repository.getDetail(id))!;

      expect(latestAny.cylinderRevision, 1);
      expect(latestCurrent.cylinderRevision, 2);
      expect(detail.summary.calculation, isNotNull);
      expect(detail.summary.latestReading!.cylinderRevision, 2);
      expect(detail.summary.awaitingReplacementReading, isFalse);
      expect(detail.summary.calculation!.displayRemainingGrams, 4000);
    },
  );

  test(
    'previous-reading lookup follows chronological order and excludes the edited row',
    () async {
      final id = await seedCylinder();
      final cylinder = (await repository.getCylinder(id))!;
      final firstId = await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 1, 10).millisecondsSinceEpoch,
        totalWeightGrams: 15000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );
      final secondId = await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 2, 10).millisecondsSinceEpoch,
        totalWeightGrams: 14500,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );
      final second = (await repository.getReading(secondId))!;

      final previous = await repository.getPreviousReadingBefore(
        cylinderId: id,
        revision: cylinder.currentRevision,
        measuredAtEpochMs: second.measuredAtEpochMs,
        createdAtEpochMs: second.createdAtEpochMs,
        excludingReadingId: second.id,
      );

      expect(previous, isNotNull);
      expect(previous!.id, firstId);
    },
  );

  test(
    'previous-reading lookup respects a proposed back-dated edit position',
    () async {
      final id = await seedCylinder();
      final cylinder = (await repository.getCylinder(id))!;
      final firstId = await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 1, 10).millisecondsSinceEpoch,
        totalWeightGrams: 15000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );
      await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 3, 10).millisecondsSinceEpoch,
        totalWeightGrams: 14000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );
      final editedId = await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 4, 10).millisecondsSinceEpoch,
        totalWeightGrams: 13500,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );
      final edited = (await repository.getReading(editedId))!;

      final previous = await repository.getPreviousReadingBefore(
        cylinderId: id,
        revision: cylinder.currentRevision,
        measuredAtEpochMs: DateTime(2026, 10, 2, 10).millisecondsSinceEpoch,
        createdAtEpochMs: edited.createdAtEpochMs,
        excludingReadingId: edited.id,
      );

      expect(previous, isNotNull);
      expect(previous!.id, firstId);
    },
  );

  test(
    'stale metadata save cannot roll back a physical replacement revision',
    () async {
      final id = await seedCylinder();
      final stale = (await repository.getCylinder(id))!;

      await repository.replaceCylinder(
        cylinder: stale,
        newTareGrams: 8000,
        newCapacityGrams: 9000,
        unit: MassUnit.kg,
      );

      await expectLater(
        repository.updateCylinder(stale.copyWith(name: 'Stale edit')),
        throwsA(isA<CylinderStateConflictException>()),
      );

      final current = (await repository.getCylinder(id))!;
      expect(current.currentRevision, 2);
      expect(current.tareGrams, 8000);
      expect(current.capacityGrams, 9000);
      expect(current.name, 'BBQ');
    },
  );

  test(
    'stale spec correction cannot rewrite the new physical cylinder',
    () async {
      final id = await seedCylinder();
      final stale = (await repository.getCylinder(id))!;

      await repository.replaceCylinder(
        cylinder: stale,
        newTareGrams: 8000,
        newCapacityGrams: 9000,
        unit: MassUnit.kg,
      );

      await expectLater(
        repository.correctCylinderSpecs(
          cylinder: stale.copyWith(name: 'Old physical cylinder'),
          newTareGrams: 11000,
          newCapacityGrams: 7000,
          unit: MassUnit.kg,
        ),
        throwsA(isA<CylinderStateConflictException>()),
      );

      final current = (await repository.getCylinder(id))!;
      expect(current.currentRevision, 2);
      expect(current.tareGrams, 8000);
      expect(current.capacityGrams, 9000);
      expect(current.name, 'BBQ');
    },
  );

  test(
    'stale replacement request cannot double-replace from an old revision',
    () async {
      final id = await seedCylinder();
      final stale = (await repository.getCylinder(id))!;

      await repository.replaceCylinder(
        cylinder: stale,
        newTareGrams: 8000,
        newCapacityGrams: 9000,
        unit: MassUnit.kg,
      );

      await expectLater(
        repository.replaceCylinder(
          cylinder: stale,
          newTareGrams: 7000,
          newCapacityGrams: 8000,
          unit: MassUnit.kg,
        ),
        throwsA(isA<CylinderStateConflictException>()),
      );

      final current = (await repository.getCylinder(id))!;
      expect(current.currentRevision, 2);
      expect(current.tareGrams, 8000);
      expect(current.capacityGrams, 9000);
    },
  );

  test(
    'stale add-reading screen cannot save against a replaced cylinder',
    () async {
      final id = await seedCylinder();
      final stale = (await repository.getCylinder(id))!;

      await repository.replaceCylinder(
        cylinder: stale,
        newTareGrams: 8000,
        newCapacityGrams: 9000,
        unit: MassUnit.kg,
      );

      await expectLater(
        repository.addReading(
          cylinder: stale,
          measuredAtEpochMs: DateTime(2026, 10, 9).millisecondsSinceEpoch,
          totalWeightGrams: 15000,
          eventType: ReadingEventType.normal,
          validationFlag: ReadingValidationFlag.normal,
          excludedFromPrediction: false,
        ),
        throwsA(isA<CylinderStateConflictException>()),
      );

      expect(await repository.listReadings(id), isEmpty);
      expect((await repository.getAdState()).completedReadingCount, 0);
    },
  );

  test(
    'stale reading edit cannot restore snapshots changed by spec correction',
    () async {
      final id = await seedCylinder();
      var cylinder = (await repository.getCylinder(id))!;
      final readingId = await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
        totalWeightGrams: 15000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );
      final staleReading = (await repository.getReading(readingId))!;

      await repository.correctCylinderSpecs(
        cylinder: cylinder,
        newTareGrams: 11000,
        newCapacityGrams: 9000,
        unit: MassUnit.kg,
      );
      cylinder = (await repository.getCylinder(id))!;

      await expectLater(
        repository.updateReading(
          reading: staleReading,
          measuredAtEpochMs: DateTime(2026, 10, 2).millisecondsSinceEpoch,
          totalWeightGrams: 14500,
          eventType: ReadingEventType.normal,
          validationFlag: ReadingValidationFlag.normal,
          excludedFromPrediction: false,
        ),
        throwsA(isA<ReadingStateConflictException>()),
      );

      final currentReading = (await repository.getReading(readingId))!;
      expect(currentReading.tareGramsSnapshot, 11000);
      expect(currentReading.capacityGramsSnapshot, 9000);
      expect(currentReading.totalWeightGrams, 15000);
      expect(currentReading.cylinderRevision, cylinder.currentRevision);
    },
  );

  test(
    'unexplained normal increase is conservatively excluded in storage',
    () async {
      final id = await seedCylinder();
      final cylinder = (await repository.getCylinder(id))!;
      await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
        totalWeightGrams: 15000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );
      final secondId = await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 2).millisecondsSinceEpoch,
        totalWeightGrams: 16000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );

      final second = (await repository.getReading(secondId))!;
      expect(second.isExcludedFromPrediction, isTrue);
      expect(
        second.predictionExclusionReason,
        PredictionExclusionReason.sequenceIncrease,
      );
    },
  );

  test(
    'automatic sequence exclusion clears when chronology is corrected',
    () async {
      final id = await seedCylinder();
      final cylinder = (await repository.getCylinder(id))!;
      final firstId = await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
        totalWeightGrams: 15000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );
      final secondId = await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 2).millisecondsSinceEpoch,
        totalWeightGrams: 16000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );

      expect(
        (await repository.getReading(secondId))!.predictionExclusionReason,
        PredictionExclusionReason.sequenceIncrease,
      );

      final first = (await repository.getReading(firstId))!;
      await repository.updateReading(
        reading: first,
        measuredAtEpochMs: first.measuredAtEpochMs,
        totalWeightGrams: 17000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );

      final repaired = (await repository.getReading(secondId))!;
      expect(repaired.isExcludedFromPrediction, isFalse);
      expect(
        repaired.predictionExclusionReason,
        PredictionExclusionReason.none,
      );
    },
  );

  test('explicit refill boundary is not sequence-excluded', () async {
    final id = await seedCylinder();
    final cylinder = (await repository.getCylinder(id))!;
    await repository.addReading(
      cylinder: cylinder,
      measuredAtEpochMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
      totalWeightGrams: 15000,
      eventType: ReadingEventType.normal,
      validationFlag: ReadingValidationFlag.normal,
      excludedFromPrediction: false,
    );
    final refillId = await repository.addReading(
      cylinder: cylinder,
      measuredAtEpochMs: DateTime(2026, 10, 2).millisecondsSinceEpoch,
      totalWeightGrams: 18000,
      eventType: ReadingEventType.refill,
      validationFlag: ReadingValidationFlag.normal,
      excludedFromPrediction: false,
    );

    final refill = (await repository.getReading(refillId))!;
    expect(refill.isExcludedFromPrediction, isFalse);
  });

  test(
    'editing an earlier reading can conservatively exclude the following normal reading',
    () async {
      final id = await seedCylinder();
      final cylinder = (await repository.getCylinder(id))!;
      final firstId = await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
        totalWeightGrams: 17000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );
      final secondId = await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 2).millisecondsSinceEpoch,
        totalWeightGrams: 16000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );
      var first = (await repository.getReading(firstId))!;
      expect(
        (await repository.getReading(secondId))!.isExcludedFromPrediction,
        isFalse,
      );

      await repository.updateReading(
        reading: first,
        measuredAtEpochMs: first.measuredAtEpochMs,
        totalWeightGrams: 14000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );

      final second = (await repository.getReading(secondId))!;
      expect(second.isExcludedFromPrediction, isTrue);
    },
  );

  test(
    'deleting a middle reading repairs newly exposed unexplained increase',
    () async {
      final id = await seedCylinder();
      final cylinder = (await repository.getCylinder(id))!;
      await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
        totalWeightGrams: 14000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );
      final middleId = await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 2).millisecondsSinceEpoch,
        totalWeightGrams: 17000,
        eventType: ReadingEventType.refill,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );
      final lastId = await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: DateTime(2026, 10, 3).millisecondsSinceEpoch,
        totalWeightGrams: 16000,
        eventType: ReadingEventType.normal,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );
      expect(
        (await repository.getReading(lastId))!.isExcludedFromPrediction,
        isFalse,
      );

      await repository.deleteReading(middleId);

      final last = (await repository.getReading(lastId))!;
      expect(last.isExcludedFromPrediction, isTrue);
    },
  );

  test(
    'repository rejects invalid cylinder data even when UI validation is bypassed',
    () async {
      await expectLater(
        repository.createCylinder(
          name: '   ',
          useCase: CylinderUseCase.bbq,
          preferredUnit: MassUnit.kg,
          tareGrams: 10000,
          capacityGrams: 10000,
          lowThresholdPct: 20,
        ),
        throwsA(isA<RepositoryInvariantException>()),
      );

      await expectLater(
        repository.createCylinder(
          name: 'Portable',
          useCase: CylinderUseCase.bbq,
          preferredUnit: MassUnit.kg,
          tareGrams: 300000,
          capacityGrams: 300000,
          lowThresholdPct: 20,
        ),
        throwsA(isA<RepositoryInvariantException>()),
      );

      await expectLater(
        repository.createCylinder(
          name: 'Portable',
          useCase: CylinderUseCase.bbq,
          preferredUnit: MassUnit.kg,
          tareGrams: 10000,
          capacityGrams: 10000,
          lowThresholdPct: 90,
        ),
        throwsA(isA<RepositoryInvariantException>()),
      );
    },
  );

  test(
    'repository rejects a reading whose claimed validation flag is inconsistent',
    () async {
      final id = await seedCylinder();
      final cylinder = (await repository.getCylinder(id))!;

      await expectLater(
        repository.addReading(
          cylinder: cylinder,
          measuredAtEpochMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
          totalWeightGrams: 20500,
          eventType: ReadingEventType.normal,
          validationFlag: ReadingValidationFlag.normal,
          excludedFromPrediction: false,
        ),
        throwsA(isA<RepositoryInvariantException>()),
      );
      expect(await repository.getLatestReading(id), isNull);
    },
  );

  test(
    'repository rejects below-tare reading even when called directly',
    () async {
      final id = await seedCylinder();
      final cylinder = (await repository.getCylinder(id))!;

      await expectLater(
        repository.addReading(
          cylinder: cylinder,
          measuredAtEpochMs: DateTime(2026, 10, 1).millisecondsSinceEpoch,
          totalWeightGrams: 9000,
          eventType: ReadingEventType.normal,
          validationFlag: ReadingValidationFlag.normal,
          excludedFromPrediction: false,
        ),
        throwsA(isA<RepositoryInvariantException>()),
      );
      expect(await repository.getLatestReading(id), isNull);
    },
  );

  test('guarded cylinder delete rejects a stale physical revision', () async {
    final id = await seedCylinder();
    final original = (await repository.getCylinder(id))!;
    final reminder = await repository.getReminder(id);

    await repository.replaceCylinder(
      cylinder: original,
      newTareGrams: 11000,
      newCapacityGrams: 9000,
      unit: MassUnit.kg,
    );

    await expectLater(
      repository.deleteCylinder(id, expectedRevision: original.currentRevision),
      throwsA(isA<CylinderStateConflictException>()),
    );

    expect(await repository.getCylinder(id), isNotNull);
    final stillThere = await repository.getReminder(id);
    expect(stillThere.notificationId, reminder.notificationId);
  });

  test(
    'guarded cylinder delete returns notification id after commit',
    () async {
      final id = await seedCylinder();
      final cylinder = (await repository.getCylinder(id))!;
      final reminder = await repository.getReminder(id);

      final notificationId = await repository.deleteCylinder(
        id,
        expectedRevision: cylinder.currentRevision,
      );

      expect(notificationId, reminder.notificationId);
      expect(await repository.getCylinder(id), isNull);
    },
  );
}
