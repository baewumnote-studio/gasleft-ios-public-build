import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/app_config.dart';

class AppDatabase {
  AppDatabase({
    DatabaseFactory? databaseFactoryOverride,
    String? databasePathOverride,
  }) : // Keep the public injection parameter names and private fields.
       // ignore: prefer_initializing_formals
       _databaseFactoryOverride = databaseFactoryOverride,
       // ignore: prefer_initializing_formals
       _databasePathOverride = databasePathOverride;

  final DatabaseFactory? _databaseFactoryOverride;
  final String? _databasePathOverride;
  Database? _database;
  Future<Database>? _opening;

  /// Opens the SQLite handle once even when multiple providers request it
  /// during the first Flutter frame. Caching only the completed Database would
  /// allow two callers to enter [_open] before either assignment completes.
  Future<Database> get db async {
    final current = _database;
    if (current != null) return current;

    final inFlight = _opening;
    if (inFlight != null) return inFlight;

    final opening = _open().then((opened) {
      // Include assignment in the shared Future so close() waiting on an
      // in-flight open can never race past this state transition.
      _database = opened;
      return opened;
    });
    _opening = opening;
    try {
      return await opening;
    } finally {
      if (identical(_opening, opening)) _opening = null;
    }
  }

  Future<Database> _open() async {
    final factory = _databaseFactoryOverride ?? databaseFactory;
    final path =
        _databasePathOverride ??
        p.join(await getDatabasesPath(), AppConfig.databaseName);
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: AppConfig.databaseVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await _createV3(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _migrateV1ToV2(database);
          }
          if (oldVersion < 3) {
            await _migrateV2ToV3(database);
          }
        },
      ),
    );
  }

  Future<void> _createV3(Database database) async {
    await database.execute('''
      CREATE TABLE cylinders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        use_case TEXT NOT NULL,
        preferred_unit TEXT NOT NULL,
        tare_grams INTEGER NOT NULL,
        capacity_grams INTEGER NOT NULL,
        low_threshold_pct REAL NOT NULL,
        current_revision INTEGER NOT NULL,
        sort_order INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE weight_readings (
        id TEXT PRIMARY KEY,
        cylinder_id TEXT NOT NULL,
        measured_at_ms INTEGER NOT NULL,
        total_weight_grams INTEGER NOT NULL,
        tare_grams_snapshot INTEGER NOT NULL,
        capacity_grams_snapshot INTEGER NOT NULL,
        cylinder_revision INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        validation_flag TEXT NOT NULL,
        excluded_from_prediction INTEGER NOT NULL DEFAULT 0,
        prediction_exclusion_reason TEXT NOT NULL DEFAULT 'none',
        note TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        FOREIGN KEY(cylinder_id) REFERENCES cylinders(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE INDEX idx_weight_readings_cylinder_date
      ON weight_readings(cylinder_id, measured_at_ms DESC)
    ''');

    await database.execute('''
      CREATE TABLE reminder_settings (
        cylinder_id TEXT PRIMARY KEY,
        recheck_enabled INTEGER NOT NULL DEFAULT 0,
        recheck_days INTEGER NOT NULL DEFAULT 14,
        notification_id INTEGER NOT NULL UNIQUE,
        updated_at_ms INTEGER NOT NULL,
        FOREIGN KEY(cylinder_id) REFERENCES cylinders(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE app_settings (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        theme_mode TEXT NOT NULL,
        default_unit TEXT NOT NULL,
        onboarding_complete INTEGER NOT NULL DEFAULT 0,
        notification_permission_asked INTEGER NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE ad_state (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        completed_reading_count INTEGER NOT NULL DEFAULT 0,
        interstitial_impression_count INTEGER NOT NULL DEFAULT 0,
        last_interstitial_at_ms INTEGER,
        last_interstitial_day_key TEXT,
        daily_interstitial_count INTEGER NOT NULL DEFAULT 0,
        first_session_completed INTEGER NOT NULL DEFAULT 0,
        last_eligible_reading_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    final now = DateTime.now().millisecondsSinceEpoch;
    await database.insert('app_settings', {
      'id': 1,
      'theme_mode': 'system',
      'default_unit': 'kg',
      'onboarding_complete': 0,
      'notification_permission_asked': 0,
      'created_at_ms': now,
      'updated_at_ms': now,
    });
    await database.insert('ad_state', {
      'id': 1,
      'completed_reading_count': 0,
      'interstitial_impression_count': 0,
      'last_interstitial_at_ms': null,
      'last_interstitial_day_key': null,
      'daily_interstitial_count': 0,
      'first_session_completed': 0,
      'last_eligible_reading_count': 0,
    });
  }

  /// v1 allowed duplicate notification IDs. v2 makes them UNIQUE so one
  /// cylinder can never overwrite/cancel another cylinder's local reminder.
  /// Existing IDs are preserved whenever possible; only collisions move to the
  /// next free positive 31-bit integer.
  Future<void> _migrateV1ToV2(Database database) async {
    final rows = await database.query(
      'reminder_settings',
      orderBy: 'cylinder_id ASC',
    );

    await database.execute(
      'ALTER TABLE reminder_settings RENAME TO reminder_settings_v1',
    );
    await database.execute('''
      CREATE TABLE reminder_settings (
        cylinder_id TEXT PRIMARY KEY,
        recheck_enabled INTEGER NOT NULL DEFAULT 0,
        recheck_days INTEGER NOT NULL DEFAULT 14,
        notification_id INTEGER NOT NULL UNIQUE,
        updated_at_ms INTEGER NOT NULL,
        FOREIGN KEY(cylinder_id) REFERENCES cylinders(id) ON DELETE CASCADE
      )
    ''');

    final occupied = <int>{};
    for (final row in rows) {
      var candidate = (row['notification_id'] as int) & 0x7fffffff;
      if (candidate == 0) candidate = 1;
      while (occupied.contains(candidate)) {
        candidate = candidate == 0x7fffffff ? 1 : candidate + 1;
      }
      occupied.add(candidate);
      await database.insert('reminder_settings', {
        'cylinder_id': row['cylinder_id'],
        'recheck_enabled': row['recheck_enabled'],
        'recheck_days': row['recheck_days'],
        'notification_id': candidate,
        'updated_at_ms': row['updated_at_ms'],
      });
    }

    await database.execute('DROP TABLE reminder_settings_v1');
  }

  /// v2 stored only a boolean prediction exclusion. v3 records why a
  /// reading is excluded so chronology repair can clear only automatic
  /// sequence exclusions while preserving explicit/manual exclusions.
  Future<void> _migrateV2ToV3(Database database) async {
    final columns = await database.rawQuery(
      'PRAGMA table_info(weight_readings)',
    );
    final hasReason = columns.any(
      (column) => column['name'] == 'prediction_exclusion_reason',
    );
    if (!hasReason) {
      await database.execute(
        "ALTER TABLE weight_readings ADD COLUMN prediction_exclusion_reason TEXT NOT NULL DEFAULT 'none'",
      );
    }

    final rows = await database.query(
      'weight_readings',
      orderBy:
          'cylinder_id ASC, cylinder_revision ASC, measured_at_ms ASC, created_at_ms ASC',
    );

    String? previousKey;
    int? previousTotal;
    for (final row in rows) {
      final key = '${row['cylinder_id']}#${row['cylinder_revision']}';
      if (key != previousKey) {
        previousKey = key;
        previousTotal = null;
      }

      final excluded = (row['excluded_from_prediction'] as int? ?? 0) == 1;
      final validationFlag = row['validation_flag'] as String? ?? 'normal';
      final eventType = row['event_type'] as String? ?? 'normal';
      final total = row['total_weight_grams'] as int;
      final capacity = row['capacity_grams_snapshot'] as int;

      var reason = 'none';
      if (excluded) {
        if (validationFlag == 'aboveNominalFull') {
          reason = 'validation';
        } else if (eventType == 'normal' && previousTotal != null) {
          final onePercentNoise = (capacity * 0.01).round();
          final noiseGrams = onePercentNoise > 50 ? onePercentNoise : 50;
          reason = total > previousTotal + noiseGrams
              ? 'sequenceIncrease'
              : 'manual';
        } else {
          reason = 'manual';
        }
      }

      await database.update(
        'weight_readings',
        {'prediction_exclusion_reason': reason},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      previousTotal = total;
    }
  }

  Future<void> close() async {
    final inFlight = _opening;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {
        // If opening itself failed there is no handle to close.
      }
    }
    await _database?.close();
    _database = null;
    _opening = null;
  }
}
