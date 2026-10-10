import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import '../core/enums.dart';
import '../domain/models/cylinder.dart';
import '../domain/models/settings_models.dart';
import '../domain/models/view_models.dart';
import '../domain/models/weight_reading.dart';
import '../domain/services/cylinder_spec_validation_service.dart';
import '../domain/services/gas_calculation_service.dart';
import '../domain/services/reading_validation_service.dart';
import '../services/notification_id_allocator.dart';
import 'app_database.dart';

class CylinderSpecCorrectionException implements Exception {
  const CylinderSpecCorrectionException(this.messageKey);
  final String messageKey;

  @override
  String toString() => messageKey;
}

/// Raised when a screen attempts to save against a physical-cylinder revision
/// that changed after the screen loaded. Silently writing the stale model could
/// roll a replacement revision/specification back to an older state.
class CylinderStateConflictException implements Exception {
  const CylinderStateConflictException([
    this.messageKey = 'cylinderChangedWhileEditing',
  ]);

  final String messageKey;

  @override
  String toString() => messageKey;
}

class ReadingStateConflictException implements Exception {
  const ReadingStateConflictException([
    this.messageKey = 'readingChangedWhileEditing',
  ]);

  final String messageKey;

  @override
  String toString() => messageKey;
}

/// Defensive repository boundary for invariants that normal UI validation has
/// already checked. Keeping the persistence layer strict prevents later code,
/// migrations, tests, or deep-link flows from silently storing impossible
/// cylinder/reading data.
class RepositoryInvariantException implements Exception {
  const RepositoryInvariantException(this.messageKey);

  final String messageKey;

  @override
  String toString() => messageKey;
}

class GasRepository {
  GasRepository(this._database);

  final AppDatabase _database;
  static const _uuid = Uuid();

  static void _validateCylinderMutation({
    required String name,
    required int tareGrams,
    required int capacityGrams,
    required double lowThresholdPct,
  }) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || normalizedName.length > 40) {
      throw const RepositoryInvariantException('validationCylinderName');
    }
    if (!lowThresholdPct.isFinite ||
        lowThresholdPct < 5 ||
        lowThresholdPct > 50) {
      throw const RepositoryInvariantException('validationLowThreshold');
    }
    final validation = CylinderSpecValidationService.validate(
      tareGrams: tareGrams,
      capacityGrams: capacityGrams,
    );
    if (!validation.isValid) {
      throw RepositoryInvariantException(
        validation.messageKey ?? 'checkValues',
      );
    }
  }

  static void _validateReadingMutation({
    required int tareGrams,
    required int capacityGrams,
    required int totalWeightGrams,
    required MassUnit unit,
    required ReadingValidationFlag claimedFlag,
  }) {
    final validation = ReadingValidationService.validate(
      tareGrams: tareGrams,
      capacityGrams: capacityGrams,
      currentTotalGrams: totalWeightGrams,
      inputUnit: unit,
    );
    if (!validation.canSave) {
      throw RepositoryInvariantException(
        validation.messageKey ?? 'checkInputGeneric',
      );
    }
    if (validation.flag != claimedFlag) {
      throw const RepositoryInvariantException('readingValidationMismatch');
    }
  }

  Future<AppSettings> getAppSettings() async {
    final db = await _database.db;
    return db.transaction((txn) async {
      var rows = await txn.query('app_settings', where: 'id = 1', limit: 1);
      if (rows.isEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final cylinderRows = await txn.query(
          'cylinders',
          columns: ['preferred_unit'],
          orderBy: 'sort_order ASC, created_at_ms ASC',
          limit: 1,
        );
        final hasCylinderData = cylinderRows.isNotEmpty;
        final recoveredUnit = hasCylinderData
            ? MassUnit.fromDb(cylinderRows.single['preferred_unit']! as String)
            : MassUnit.kg;
        await txn.insert('app_settings', {
          'id': 1,
          'theme_mode': AppThemeMode.system.name,
          'default_unit': recoveredUnit.name,
          // Existing cylinder data proves onboarding was completed before
          // the singleton row was lost; do not send that user through setup
          // again just because settings storage needs repair.
          'onboarding_complete': hasCylinderData ? 1 : 0,
          'notification_permission_asked': 0,
          'created_at_ms': now,
          'updated_at_ms': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        rows = await txn.query('app_settings', where: 'id = 1', limit: 1);
      }
      if (rows.isEmpty) {
        throw StateError('Unable to recover app settings singleton row.');
      }
      return AppSettings.fromMap(rows.single);
    });
  }

  Future<void> saveAppSettings(AppSettings settings) async {
    final db = await _database.db;
    await db.update('app_settings', settings.toMap(), where: 'id = 1');
  }

  Future<void> markOnboardingComplete() async {
    final db = await _database.db;
    await db.rawUpdate(
      '''
      UPDATE app_settings
      SET onboarding_complete = 1, updated_at_ms = ?
      WHERE id = 1 AND onboarding_complete = 0
    ''',
      [DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> markNotificationPermissionAsked() async {
    final db = await _database.db;
    await db.update('app_settings', {
      'notification_permission_asked': 1,
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = 1');
  }

  Future<void> updateDefaultUnit(MassUnit unit) async {
    final db = await _database.db;
    await db.update('app_settings', {
      'default_unit': unit.name,
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = 1');
  }

  Future<void> updateThemeMode(AppThemeMode mode) async {
    final db = await _database.db;
    await db.update('app_settings', {
      'theme_mode': mode.name,
      'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
    }, where: 'id = 1');
  }

  Future<AdState> getAdState() async {
    final db = await _database.db;
    return db.transaction((txn) async {
      var rows = await txn.query('ad_state', where: 'id = 1', limit: 1);
      if (rows.isEmpty) {
        await txn.insert('ad_state', {
          'id': 1,
          'completed_reading_count': 0,
          'interstitial_impression_count': 0,
          'last_interstitial_at_ms': null,
          'last_interstitial_day_key': null,
          'daily_interstitial_count': 0,
          'first_session_completed': 0,
          'last_eligible_reading_count': 0,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        rows = await txn.query('ad_state', where: 'id = 1', limit: 1);
      }
      if (rows.isEmpty) {
        throw StateError('Unable to recover ad-state singleton row.');
      }
      return AdState.fromMap(rows.single);
    });
  }

  Future<void> saveAdState(AdState state) async {
    final db = await _database.db;
    await db.update('ad_state', state.toMap(), where: 'id = 1');
  }

  /// Records one actual interstitial impression without writing a stale
  /// snapshot of reading/session counters back over newer database values.
  Future<void> recordInterstitialImpression({
    required int atEpochMs,
    required String dayKey,
  }) async {
    final db = await _database.db;
    await db.rawUpdate(
      '''
      UPDATE ad_state
      SET interstitial_impression_count = interstitial_impression_count + 1,
          last_interstitial_at_ms = ?,
          daily_interstitial_count = CASE
            WHEN last_interstitial_day_key = ?
              THEN daily_interstitial_count + 1
            ELSE 1
          END,
          last_interstitial_day_key = ?,
          last_eligible_reading_count = completed_reading_count
      WHERE id = 1
    ''',
      [atEpochMs, dayKey, dayKey],
    );
  }

  Future<void> markFirstSessionCompleted() async {
    final db = await _database.db;
    // Partial SQL update avoids overwriting a reading/impression counter if a
    // lifecycle callback and ad-state mutation ever overlap. Idempotent by
    // construction.
    await db.rawUpdate('''
      UPDATE ad_state
      SET first_session_completed = 1
      WHERE id = 1 AND first_session_completed = 0
    ''');
  }

  Future<List<Cylinder>> listCylinders() async {
    final db = await _database.db;
    final rows = await db.query(
      'cylinders',
      orderBy: 'sort_order ASC, created_at_ms ASC',
    );
    return rows.map(Cylinder.fromMap).toList();
  }

  Future<Cylinder?> getCylinder(String id) async {
    final db = await _database.db;
    final rows = await db.query(
      'cylinders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Cylinder.fromMap(rows.single);
  }

  Future<String> createCylinder({
    required String name,
    required CylinderUseCase useCase,
    required MassUnit preferredUnit,
    required int tareGrams,
    required int capacityGrams,
    required double lowThresholdPct,
  }) async {
    _validateCylinderMutation(
      name: name,
      tareGrams: tareGrams,
      capacityGrams: capacityGrams,
      lowThresholdPct: lowThresholdPct,
    );
    final db = await _database.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    await db.transaction((txn) async {
      // Allocate ordering inside the same serialized transaction as insertion
      // so two rapid creates cannot receive the same sort order.
      final sortRows = await txn.rawQuery(
        'SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order FROM cylinders',
      );
      final sortOrder = Sqflite.firstIntValue(sortRows) ?? 0;
      final cylinder = Cylinder(
        id: id,
        name: name.trim(),
        useCase: useCase,
        preferredUnit: preferredUnit,
        tareGrams: tareGrams,
        capacityGrams: capacityGrams,
        lowThresholdPct: lowThresholdPct,
        currentRevision: 1,
        sortOrder: sortOrder,
        createdAtEpochMs: now,
        updatedAtEpochMs: now,
      );
      await txn.insert('cylinders', cylinder.toMap());
      final occupiedRows = await txn.query(
        'reminder_settings',
        columns: ['notification_id'],
      );
      final occupiedIds = occupiedRows
          .map((row) => row['notification_id'] as int)
          .toSet();
      final notificationId = NotificationIdAllocator.nextAvailable(
        id,
        occupiedIds,
      );
      await txn.insert('reminder_settings', {
        'cylinder_id': id,
        'recheck_enabled': 0,
        'recheck_days': AppConfig.defaultRecheckDays,
        'notification_id': notificationId,
        'updated_at_ms': now,
      });
    });
    return id;
  }

  /// Updates user-editable metadata without writing identity/specification
  /// fields from a potentially stale screen model back over the database.
  Future<void> updateCylinder(Cylinder cylinder) async {
    _validateCylinderMutation(
      name: cylinder.name,
      tareGrams: cylinder.tareGrams,
      capacityGrams: cylinder.capacityGrams,
      lowThresholdPct: cylinder.lowThresholdPct,
    );
    final db = await _database.db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'cylinders',
        columns: ['current_revision'],
        where: 'id = ?',
        whereArgs: [cylinder.id],
        limit: 1,
      );
      if (rows.isEmpty) throw const CylinderStateConflictException();
      final currentRevision = rows.single['current_revision']! as int;
      if (currentRevision != cylinder.currentRevision) {
        throw const CylinderStateConflictException();
      }

      await txn.update(
        'cylinders',
        {
          'name': cylinder.name.trim(),
          'use_case': cylinder.useCase.name,
          'preferred_unit': cylinder.preferredUnit.name,
          'low_threshold_pct': cylinder.lowThresholdPct,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ? AND current_revision = ?',
        whereArgs: [cylinder.id, cylinder.currentRevision],
      );
    });
  }

  /// Corrects metadata for the *same physical cylinder*.
  ///
  /// Weight readings in the current cylinder revision were measured from the
  /// same physical cylinder, so their tare/capacity snapshots must be updated
  /// as well. This is intentionally different from [replaceCylinder], which
  /// starts a new revision and preserves older snapshots unchanged.
  Future<void> correctCylinderSpecs({
    required Cylinder cylinder,
    required int newTareGrams,
    required int newCapacityGrams,
    required MassUnit unit,
  }) async {
    _validateCylinderMutation(
      name: cylinder.name,
      tareGrams: newTareGrams,
      capacityGrams: newCapacityGrams,
      lowThresholdPct: cylinder.lowThresholdPct,
    );
    final db = await _database.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final cylinderRows = await txn.query(
        'cylinders',
        where: 'id = ?',
        whereArgs: [cylinder.id],
        limit: 1,
      );
      if (cylinderRows.isEmpty) throw const CylinderStateConflictException();
      final current = Cylinder.fromMap(cylinderRows.single);
      if (current.currentRevision != cylinder.currentRevision) {
        throw const CylinderStateConflictException();
      }

      final rows = await txn.query(
        'weight_readings',
        where: 'cylinder_id = ? AND cylinder_revision = ?',
        whereArgs: [cylinder.id, current.currentRevision],
      );

      final validations = <String, ReadingValidationResult>{};
      for (final row in rows) {
        final reading = WeightReading.fromMap(row);
        final validation = ReadingValidationService.validate(
          tareGrams: newTareGrams,
          capacityGrams: newCapacityGrams,
          currentTotalGrams: reading.totalWeightGrams,
          inputUnit: unit,
        );
        if (!validation.canSave) {
          throw const CylinderSpecCorrectionException(
            'correctionExistingBelowTare',
          );
        }
        validations[reading.id] = validation;
      }

      // Write only the fields this edit owns. Keep revision/order/creation
      // identity from the database instead of copying a screen snapshot back.
      await txn.update(
        'cylinders',
        {
          'name': cylinder.name.trim(),
          'use_case': cylinder.useCase.name,
          'preferred_unit': unit.name,
          'tare_grams': newTareGrams,
          'capacity_grams': newCapacityGrams,
          'low_threshold_pct': cylinder.lowThresholdPct,
          'updated_at_ms': now,
        },
        where: 'id = ? AND current_revision = ?',
        whereArgs: [cylinder.id, current.currentRevision],
      );

      for (final row in rows) {
        final reading = WeightReading.fromMap(row);
        final validation = validations[reading.id]!;
        final correctedReason =
            validation.flag == ReadingValidationFlag.aboveNominalFull
            ? PredictionExclusionReason.validation
            : reading.predictionExclusionReason ==
                  PredictionExclusionReason.manual
            ? PredictionExclusionReason.manual
            : PredictionExclusionReason.none;
        await txn.update(
          'weight_readings',
          {
            'tare_grams_snapshot': newTareGrams,
            'capacity_grams_snapshot': newCapacityGrams,
            'validation_flag': validation.flag.name,
            'excluded_from_prediction':
                correctedReason == PredictionExclusionReason.none ? 0 : 1,
            'prediction_exclusion_reason': correctedReason.name,
            'updated_at_ms': now,
          },
          where: 'id = ?',
          whereArgs: [reading.id],
        );
      }

      await _repairPredictionExclusionsForRevision(
        txn,
        cylinderId: cylinder.id,
        revision: current.currentRevision,
      );
    });
  }

  Future<void> replaceCylinder({
    required Cylinder cylinder,
    required int newTareGrams,
    required int newCapacityGrams,
    required MassUnit unit,
  }) async {
    _validateCylinderMutation(
      name: cylinder.name,
      tareGrams: newTareGrams,
      capacityGrams: newCapacityGrams,
      lowThresholdPct: cylinder.lowThresholdPct,
    );
    final db = await _database.db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'cylinders',
        where: 'id = ?',
        whereArgs: [cylinder.id],
        limit: 1,
      );
      if (rows.isEmpty) throw const CylinderStateConflictException();
      final current = Cylinder.fromMap(rows.single);
      if (current.currentRevision != cylinder.currentRevision) {
        throw const CylinderStateConflictException();
      }

      await txn.update(
        'cylinders',
        {
          'name': cylinder.name.trim(),
          'use_case': cylinder.useCase.name,
          'preferred_unit': unit.name,
          'tare_grams': newTareGrams,
          'capacity_grams': newCapacityGrams,
          'low_threshold_pct': cylinder.lowThresholdPct,
          'current_revision': current.currentRevision + 1,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ? AND current_revision = ?',
        whereArgs: [cylinder.id, current.currentRevision],
      );
    });
  }

  /// Deletes a cylinder and returns the local-notification ID that belonged
  /// to it so the caller can cancel the OS request *after* the database delete
  /// commits. When [expectedRevision] is supplied, a stale detail screen cannot
  /// delete a physical cylinder that was replaced in another navigation flow.
  Future<int?> deleteCylinder(String id, {int? expectedRevision}) async {
    final db = await _database.db;
    return db.transaction((txn) async {
      final reminderRows = await txn.query(
        'reminder_settings',
        columns: ['notification_id'],
        where: 'cylinder_id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final notificationId = reminderRows.isEmpty
          ? null
          : reminderRows.single['notification_id']! as int;

      final deleted = await txn.delete(
        'cylinders',
        where: expectedRevision == null
            ? 'id = ?'
            : 'id = ? AND current_revision = ?',
        whereArgs: expectedRevision == null ? [id] : [id, expectedRevision],
      );
      if (expectedRevision != null && deleted != 1) {
        throw const CylinderStateConflictException();
      }
      return deleted == 0 ? null : notificationId;
    });
  }

  Future<WeightReading?> getLatestReading(String cylinderId) async {
    final db = await _database.db;
    final rows = await db.query(
      'weight_readings',
      where: 'cylinder_id = ?',
      whereArgs: [cylinderId],
      orderBy: 'measured_at_ms DESC, created_at_ms DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : WeightReading.fromMap(rows.single);
  }

  Future<WeightReading?> getLatestReadingForRevision(
    String cylinderId,
    int revision,
  ) async {
    final db = await _database.db;
    final rows = await db.query(
      'weight_readings',
      where: 'cylinder_id = ? AND cylinder_revision = ?',
      whereArgs: [cylinderId, revision],
      orderBy: 'measured_at_ms DESC, created_at_ms DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : WeightReading.fromMap(rows.single);
  }

  Future<WeightReading?> getReading(String id) async {
    final db = await _database.db;
    final rows = await db.query(
      'weight_readings',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : WeightReading.fromMap(rows.single);
  }

  /// Returns the reading immediately before a proposed chronological position
  /// within one physical-cylinder revision.
  ///
  /// [createdAtEpochMs] is the stable tie-breaker when two readings share the
  /// same measurement minute. [excludingReadingId] is used while editing so a
  /// reading is never compared with itself.
  Future<WeightReading?> getPreviousReadingBefore({
    required String cylinderId,
    required int revision,
    required int measuredAtEpochMs,
    required int createdAtEpochMs,
    String? excludingReadingId,
  }) async {
    final db = await _database.db;
    final whereParts = <String>[
      'cylinder_id = ?',
      'cylinder_revision = ?',
      '(measured_at_ms < ? OR (measured_at_ms = ? AND created_at_ms < ?))',
    ];
    final whereArgs = <Object?>[
      cylinderId,
      revision,
      measuredAtEpochMs,
      measuredAtEpochMs,
      createdAtEpochMs,
    ];
    if (excludingReadingId != null) {
      whereParts.add('id != ?');
      whereArgs.add(excludingReadingId);
    }
    final rows = await db.query(
      'weight_readings',
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'measured_at_ms DESC, created_at_ms DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : WeightReading.fromMap(rows.single);
  }

  Future<List<WeightReading>> listReadings(String cylinderId) async {
    final db = await _database.db;
    final rows = await db.query(
      'weight_readings',
      where: 'cylinder_id = ?',
      whereArgs: [cylinderId],
      orderBy: 'measured_at_ms DESC, created_at_ms DESC',
    );
    return rows.map(WeightReading.fromMap).toList();
  }

  Future<PredictionExclusionReason> _submittedExclusionReason(
    Transaction txn, {
    required String cylinderId,
    required int revision,
    required int measuredAtEpochMs,
    required int createdAtEpochMs,
    required int totalWeightGrams,
    required int capacityGrams,
    required ReadingEventType eventType,
    required ReadingValidationFlag validationFlag,
    required bool requestedExcluded,
    String? excludingReadingId,
  }) async {
    if (validationFlag == ReadingValidationFlag.aboveNominalFull) {
      return PredictionExclusionReason.validation;
    }

    if (eventType == ReadingEventType.normal) {
      final whereParts = <String>[
        'cylinder_id = ?',
        'cylinder_revision = ?',
        '(measured_at_ms < ? OR (measured_at_ms = ? AND created_at_ms < ?))',
      ];
      final whereArgs = <Object?>[
        cylinderId,
        revision,
        measuredAtEpochMs,
        measuredAtEpochMs,
        createdAtEpochMs,
      ];
      if (excludingReadingId != null) {
        whereParts.add('id != ?');
        whereArgs.add(excludingReadingId);
      }
      final previousRows = await txn.query(
        'weight_readings',
        where: whereParts.join(' AND '),
        whereArgs: whereArgs,
        orderBy: 'measured_at_ms DESC, created_at_ms DESC',
        limit: 1,
      );
      if (previousRows.isNotEmpty) {
        final previousTotal = previousRows.single['total_weight_grams']! as int;
        final onePercentNoise = (capacityGrams * 0.01).round();
        final noiseGrams = onePercentNoise > 50 ? onePercentNoise : 50;
        if (totalWeightGrams > previousTotal + noiseGrams) {
          return PredictionExclusionReason.sequenceIncrease;
        }
      }
    }

    return requestedExcluded
        ? PredictionExclusionReason.manual
        : PredictionExclusionReason.none;
  }

  /// Recomputes automatic prediction exclusions after chronology changes.
  ///
  /// v3 stores the reason separately, so an exclusion caused only by a prior
  /// unexplained increase can be cleared when the user edits/deletes history
  /// back into a valid sequence. Explicit/manual exclusions are preserved.
  Future<void> _repairPredictionExclusionsForRevision(
    Transaction txn, {
    required String cylinderId,
    required int revision,
  }) async {
    final rows = await txn.query(
      'weight_readings',
      where: 'cylinder_id = ? AND cylinder_revision = ?',
      whereArgs: [cylinderId, revision],
      orderBy: 'measured_at_ms ASC, created_at_ms ASC',
    );

    WeightReading? previous;
    for (final row in rows) {
      final reading = WeightReading.fromMap(row);
      PredictionExclusionReason reason;
      if (reading.validationFlag == ReadingValidationFlag.aboveNominalFull) {
        reason = PredictionExclusionReason.validation;
      } else if (reading.predictionExclusionReason ==
          PredictionExclusionReason.manual) {
        reason = PredictionExclusionReason.manual;
      } else if (reading.eventType == ReadingEventType.normal &&
          previous != null) {
        final onePercentNoise = (reading.capacityGramsSnapshot * 0.01).round();
        final noiseGrams = onePercentNoise > 50 ? onePercentNoise : 50;
        reason =
            reading.totalWeightGrams > previous.totalWeightGrams + noiseGrams
            ? PredictionExclusionReason.sequenceIncrease
            : PredictionExclusionReason.none;
      } else {
        reason = PredictionExclusionReason.none;
      }

      final excluded = reason != PredictionExclusionReason.none;
      if (excluded != reading.isExcludedFromPrediction ||
          reason != reading.predictionExclusionReason) {
        await txn.update(
          'weight_readings',
          {
            'excluded_from_prediction': excluded ? 1 : 0,
            'prediction_exclusion_reason': reason.name,
            'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [reading.id],
        );
      }
      previous = reading;
    }
  }

  Future<String> addReading({
    required Cylinder cylinder,
    required int measuredAtEpochMs,
    required int totalWeightGrams,
    required ReadingEventType eventType,
    required ReadingValidationFlag validationFlag,
    required bool excludedFromPrediction,
  }) async {
    final db = await _database.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    await db.transaction((txn) async {
      final cylinderRows = await txn.query(
        'cylinders',
        where: 'id = ?',
        whereArgs: [cylinder.id],
        limit: 1,
      );
      if (cylinderRows.isEmpty) throw const CylinderStateConflictException();
      final current = Cylinder.fromMap(cylinderRows.single);
      if (current.currentRevision != cylinder.currentRevision ||
          current.tareGrams != cylinder.tareGrams ||
          current.capacityGrams != cylinder.capacityGrams) {
        throw const CylinderStateConflictException();
      }
      _validateReadingMutation(
        tareGrams: current.tareGrams,
        capacityGrams: current.capacityGrams,
        totalWeightGrams: totalWeightGrams,
        unit: current.preferredUnit,
        claimedFlag: validationFlag,
      );

      final exclusionReason = await _submittedExclusionReason(
        txn,
        cylinderId: current.id,
        revision: current.currentRevision,
        measuredAtEpochMs: measuredAtEpochMs,
        createdAtEpochMs: now,
        totalWeightGrams: totalWeightGrams,
        capacityGrams: current.capacityGrams,
        eventType: eventType,
        validationFlag: validationFlag,
        requestedExcluded: excludedFromPrediction,
      );
      final reading = WeightReading(
        id: id,
        cylinderId: current.id,
        measuredAtEpochMs: measuredAtEpochMs,
        totalWeightGrams: totalWeightGrams,
        tareGramsSnapshot: current.tareGrams,
        capacityGramsSnapshot: current.capacityGrams,
        cylinderRevision: current.currentRevision,
        eventType: eventType,
        validationFlag: validationFlag,
        isExcludedFromPrediction:
            exclusionReason != PredictionExclusionReason.none,
        predictionExclusionReason: exclusionReason,
        createdAtEpochMs: now,
        updatedAtEpochMs: now,
      );
      await txn.insert('weight_readings', reading.toMap());
      await txn.rawUpdate('''
        UPDATE ad_state
        SET completed_reading_count = completed_reading_count + 1
        WHERE id = 1
      ''');
      await _repairPredictionExclusionsForRevision(
        txn,
        cylinderId: current.id,
        revision: current.currentRevision,
      );
    });
    return id;
  }

  Future<void> updateReading({
    required WeightReading reading,
    required int measuredAtEpochMs,
    required int totalWeightGrams,
    required ReadingEventType eventType,
    required ReadingValidationFlag validationFlag,
    required bool excludedFromPrediction,
  }) async {
    final db = await _database.db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'weight_readings',
        where: 'id = ?',
        whereArgs: [reading.id],
        limit: 1,
      );
      if (rows.isEmpty) throw const ReadingStateConflictException();
      final current = WeightReading.fromMap(rows.single);
      if (current.updatedAtEpochMs != reading.updatedAtEpochMs ||
          current.cylinderRevision != reading.cylinderRevision ||
          current.tareGramsSnapshot != reading.tareGramsSnapshot ||
          current.capacityGramsSnapshot != reading.capacityGramsSnapshot) {
        throw const ReadingStateConflictException();
      }
      final cylinderRows = await txn.query(
        'cylinders',
        columns: ['preferred_unit'],
        where: 'id = ?',
        whereArgs: [current.cylinderId],
        limit: 1,
      );
      if (cylinderRows.isEmpty) throw const ReadingStateConflictException();
      _validateReadingMutation(
        tareGrams: current.tareGramsSnapshot,
        capacityGrams: current.capacityGramsSnapshot,
        totalWeightGrams: totalWeightGrams,
        unit: MassUnit.fromDb(cylinderRows.single['preferred_unit']! as String),
        claimedFlag: validationFlag,
      );

      final exclusionReason = await _submittedExclusionReason(
        txn,
        cylinderId: current.cylinderId,
        revision: current.cylinderRevision,
        measuredAtEpochMs: measuredAtEpochMs,
        createdAtEpochMs: current.createdAtEpochMs,
        totalWeightGrams: totalWeightGrams,
        capacityGrams: current.capacityGramsSnapshot,
        eventType: eventType,
        validationFlag: validationFlag,
        requestedExcluded: excludedFromPrediction,
        excludingReadingId: current.id,
      );
      final changed = await txn.update(
        'weight_readings',
        {
          'measured_at_ms': measuredAtEpochMs,
          'total_weight_grams': totalWeightGrams,
          'event_type': eventType.name,
          'validation_flag': validationFlag.name,
          'excluded_from_prediction':
              exclusionReason == PredictionExclusionReason.none ? 0 : 1,
          'prediction_exclusion_reason': exclusionReason.name,
          'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ? AND updated_at_ms = ?',
        whereArgs: [reading.id, reading.updatedAtEpochMs],
      );
      if (changed != 1) throw const ReadingStateConflictException();
      await _repairPredictionExclusionsForRevision(
        txn,
        cylinderId: current.cylinderId,
        revision: current.cylinderRevision,
      );
    });
  }

  Future<void> deleteReading(String id) async {
    final db = await _database.db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'weight_readings',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final reading = WeightReading.fromMap(rows.single);
      await txn.delete('weight_readings', where: 'id = ?', whereArgs: [id]);
      await _repairPredictionExclusionsForRevision(
        txn,
        cylinderId: reading.cylinderId,
        revision: reading.cylinderRevision,
      );
    });
  }

  Future<ReminderSettings> getReminder(String cylinderId) async {
    final db = await _database.db;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'reminder_settings',
        where: 'cylinder_id = ?',
        whereArgs: [cylinderId],
        limit: 1,
      );
      if (rows.isNotEmpty) return ReminderSettings.fromMap(rows.single);

      // Legacy/corrupt states can be missing the row. Create it inside the
      // transaction so concurrent detail/sync requests cannot double-insert.
      final cylinderRows = await txn.query(
        'cylinders',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [cylinderId],
        limit: 1,
      );
      if (cylinderRows.isEmpty) {
        throw StateError('Cannot create a reminder for a missing cylinder.');
      }

      final occupiedRows = await txn.query(
        'reminder_settings',
        columns: ['notification_id'],
      );
      final occupiedIds = occupiedRows
          .map((row) => row['notification_id'] as int)
          .toSet();
      final reminder = ReminderSettings(
        cylinderId: cylinderId,
        recheckEnabled: false,
        recheckDays: AppConfig.defaultRecheckDays,
        notificationId: NotificationIdAllocator.nextAvailable(
          cylinderId,
          occupiedIds,
        ),
        updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      );
      await txn.insert('reminder_settings', reminder.toMap());
      return reminder;
    });
  }

  Future<List<ReminderSettings>> listReminders() async {
    final db = await _database.db;
    final rows = await db.query('reminder_settings');
    return rows.map(ReminderSettings.fromMap).toList();
  }

  Future<List<ReminderSettings>> listEnabledReminders() async {
    final reminders = await listReminders();
    return reminders.where((reminder) => reminder.recheckEnabled).toList();
  }

  Future<void> saveReminder(ReminderSettings settings) async {
    final db = await _database.db;
    await db.transaction((txn) async {
      final changed = await txn.update(
        'reminder_settings',
        settings.toMap(),
        where: 'cylinder_id = ?',
        whereArgs: [settings.cylinderId],
      );
      if (changed == 0) {
        // Keep update+insert atomic. Do not use INSERT OR REPLACE here:
        // notification_id is UNIQUE and a REPLACE conflict could delete
        // another cylinder's reminder row. A uniqueness violation should fail
        // the transaction instead of mutating another cylinder.
        await txn.insert('reminder_settings', settings.toMap());
      }
    });
  }

  Future<List<CylinderSummary>> listSummaries() async {
    final cylinders = await listCylinders();
    final result = <CylinderSummary>[];
    for (final cylinder in cylinders) {
      result.add(await _buildSummary(cylinder));
    }
    return result;
  }

  Future<CylinderDetailData?> getDetail(String id) async {
    final cylinder = await getCylinder(id);
    if (cylinder == null) return null;
    return CylinderDetailData(
      cylinder: cylinder,
      summary: await _buildSummary(cylinder),
      readings: await listReadings(id),
      reminder: await getReminder(id),
    );
  }

  Future<CylinderSummary> _buildSummary(Cylinder cylinder) async {
    final latest = await getLatestReadingForRevision(
      cylinder.id,
      cylinder.currentRevision,
    );
    if (latest == null) {
      return CylinderSummary(
        cylinder: cylinder,
        status: CylinderStatus.noReading,
      );
    }
    final calc = GasCalculationService.calculate(
      tareGrams: latest.tareGramsSnapshot,
      capacityGrams: latest.capacityGramsSnapshot,
      currentTotalGrams: latest.totalWeightGrams,
    );
    return CylinderSummary(
      cylinder: cylinder,
      latestReading: latest,
      calculation: calc,
      status: ReadingValidationService.status(
        displayPercent: calc.displayPercent,
        lowThresholdPct: cylinder.lowThresholdPct,
        flag: latest.validationFlag,
      ),
    );
  }
}
