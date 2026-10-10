import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gasleft/core/app_config.dart';
import 'package:gasleft/data/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'v1 to v3 preserves reminders and resolves duplicate notification IDs',
    () async {
      final dir = await Directory.systemTemp.createTemp('gasleft_migration_');
      final path = '${dir.path}/gasleft.sqlite';

      final oldDb = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, version) async {
            await db.execute('''
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
            await db.execute('''
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
              note TEXT,
              created_at_ms INTEGER NOT NULL,
              updated_at_ms INTEGER NOT NULL,
              FOREIGN KEY(cylinder_id) REFERENCES cylinders(id) ON DELETE CASCADE
            )
          ''');
            await db.execute('''
            CREATE TABLE reminder_settings (
              cylinder_id TEXT PRIMARY KEY,
              recheck_enabled INTEGER NOT NULL DEFAULT 0,
              recheck_days INTEGER NOT NULL DEFAULT 14,
              notification_id INTEGER NOT NULL,
              updated_at_ms INTEGER NOT NULL,
              FOREIGN KEY(cylinder_id) REFERENCES cylinders(id) ON DELETE CASCADE
            )
          ''');
          },
        ),
      );

      const now = 1;
      Future<void> addCylinder(String id, int sortOrder) async {
        await oldDb.insert('cylinders', {
          'id': id,
          'name': id,
          'use_case': 'bbq',
          'preferred_unit': 'kg',
          'tare_grams': 10000,
          'capacity_grams': 9000,
          'low_threshold_pct': 20.0,
          'current_revision': 1,
          'sort_order': sortOrder,
          'created_at_ms': now,
          'updated_at_ms': now,
        });
      }

      await addCylinder('a', 0);
      await addCylinder('b', 1);
      await oldDb.insert('reminder_settings', {
        'cylinder_id': 'a',
        'recheck_enabled': 1,
        'recheck_days': 10,
        'notification_id': 42,
        'updated_at_ms': now,
      });
      await oldDb.insert('reminder_settings', {
        'cylinder_id': 'b',
        'recheck_enabled': 0,
        'recheck_days': 20,
        'notification_id': 42,
        'updated_at_ms': now,
      });
      await oldDb.close();

      final upgraded = AppDatabase(
        databaseFactoryOverride: databaseFactoryFfi,
        databasePathOverride: path,
      );
      final db = await upgraded.db;
      final rows = await db.query(
        'reminder_settings',
        orderBy: 'cylinder_id ASC',
      );

      expect(AppConfig.databaseVersion, 3);
      expect(await db.getVersion(), 3);
      expect(rows, hasLength(2));
      expect(rows[0]['cylinder_id'], 'a');
      expect(rows[0]['recheck_enabled'], 1);
      expect(rows[0]['recheck_days'], 10);
      expect(rows[0]['notification_id'], 42);
      expect(rows[1]['cylinder_id'], 'b');
      expect(rows[1]['recheck_enabled'], 0);
      expect(rows[1]['recheck_days'], 20);
      expect(rows[1]['notification_id'], isNot(42));

      final ids = rows.map((row) => row['notification_id']).toSet();
      expect(ids, hasLength(2));

      final readingColumns = await db.rawQuery(
        'PRAGMA table_info(weight_readings)',
      );
      expect(
        readingColumns.any(
          (column) => column['name'] == 'prediction_exclusion_reason',
        ),
        isTrue,
      );

      await upgraded.close();
      await dir.delete(recursive: true);
    },
  );

  test('v2 to v3 reconstructs prediction exclusion reasons', () async {
    final dir = await Directory.systemTemp.createTemp('gasleft_migration_v3_');
    final path = '${dir.path}/gasleft.sqlite';

    final oldDb = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
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
          await db.execute('''
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
              note TEXT,
              created_at_ms INTEGER NOT NULL,
              updated_at_ms INTEGER NOT NULL,
              FOREIGN KEY(cylinder_id) REFERENCES cylinders(id) ON DELETE CASCADE
            )
          ''');
        },
      ),
    );

    await oldDb.insert('cylinders', {
      'id': 'c1',
      'name': 'BBQ',
      'use_case': 'bbq',
      'preferred_unit': 'kg',
      'tare_grams': 10000,
      'capacity_grams': 9000,
      'low_threshold_pct': 20.0,
      'current_revision': 1,
      'sort_order': 0,
      'created_at_ms': 1,
      'updated_at_ms': 1,
    });

    Future<void> addReading({
      required String id,
      required int day,
      required int total,
      required String validation,
      required int excluded,
    }) async {
      await oldDb.insert('weight_readings', {
        'id': id,
        'cylinder_id': 'c1',
        'measured_at_ms': day,
        'total_weight_grams': total,
        'tare_grams_snapshot': 10000,
        'capacity_grams_snapshot': 9000,
        'cylinder_revision': 1,
        'event_type': 'normal',
        'validation_flag': validation,
        'excluded_from_prediction': excluded,
        'note': null,
        'created_at_ms': day,
        'updated_at_ms': day,
      });
    }

    await addReading(
      id: 'r1',
      day: 1,
      total: 15000,
      validation: 'normal',
      excluded: 0,
    );
    await addReading(
      id: 'r2',
      day: 2,
      total: 16000,
      validation: 'normal',
      excluded: 1,
    );
    await addReading(
      id: 'r3',
      day: 3,
      total: 14000,
      validation: 'normal',
      excluded: 1,
    );
    await addReading(
      id: 'r4',
      day: 4,
      total: 20500,
      validation: 'aboveNominalFull',
      excluded: 1,
    );
    await oldDb.close();

    final upgraded = AppDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePathOverride: path,
    );
    final db = await upgraded.db;
    final rows = await db.query(
      'weight_readings',
      orderBy: 'measured_at_ms ASC',
    );

    expect(await db.getVersion(), 3);
    expect(rows[0]['prediction_exclusion_reason'], 'none');
    expect(rows[1]['prediction_exclusion_reason'], 'sequenceIncrease');
    expect(rows[2]['prediction_exclusion_reason'], 'manual');
    expect(rows[3]['prediction_exclusion_reason'], 'validation');

    await upgraded.close();
    await dir.delete(recursive: true);
  });
}
