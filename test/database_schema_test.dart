import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gasleft/data/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase database;

  setUp(() {
    database = AppDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePathOverride: inMemoryDatabasePath,
    );
  });

  tearDown(() async => database.close());

  test(
    'v3 schema creates singleton settings, ad rows, and exclusion reasons',
    () async {
      final db = await database.db;
      final settings = await db.query('app_settings');
      final adState = await db.query('ad_state');

      expect(settings, hasLength(1));
      expect(settings.single['id'], 1);
      expect(settings.single['theme_mode'], 'system');
      expect(settings.single['default_unit'], 'kg');

      expect(adState, hasLength(1));
      expect(adState.single['id'], 1);
      expect(adState.single['completed_reading_count'], 0);
      expect(adState.single['first_session_completed'], 0);

      final columns = await db.rawQuery('PRAGMA table_info(weight_readings)');
      expect(
        columns.any(
          (column) => column['name'] == 'prediction_exclusion_reason',
        ),
        isTrue,
      );
    },
  );

  test('foreign keys are enabled and cascade child rows', () async {
    final db = await database.db;
    final foreignKeys = await db.rawQuery('PRAGMA foreign_keys');
    expect(foreignKeys.single.values.single, 1);

    await db.insert('cylinders', {
      'id': 'c1',
      'name': 'Test',
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
    await db.insert('reminder_settings', {
      'cylinder_id': 'c1',
      'recheck_enabled': 0,
      'recheck_days': 14,
      'notification_id': 10,
      'updated_at_ms': 1,
    });
    await db.delete('cylinders', where: 'id = ?', whereArgs: ['c1']);

    final reminders = await db.query('reminder_settings');
    expect(reminders, isEmpty);
  });

  test('notification ids are unique at the database boundary', () async {
    final db = await database.db;
    Future<void> addCylinder(String id, int sortOrder) async {
      await db.insert('cylinders', {
        'id': id,
        'name': id,
        'use_case': 'bbq',
        'preferred_unit': 'kg',
        'tare_grams': 10000,
        'capacity_grams': 9000,
        'low_threshold_pct': 20.0,
        'current_revision': 1,
        'sort_order': sortOrder,
        'created_at_ms': sortOrder + 1,
        'updated_at_ms': sortOrder + 1,
      });
    }

    await addCylinder('c1', 0);
    await addCylinder('c2', 1);
    await db.insert('reminder_settings', {
      'cylinder_id': 'c1',
      'recheck_enabled': 0,
      'recheck_days': 14,
      'notification_id': 77,
      'updated_at_ms': 1,
    });

    await expectLater(
      db.insert('reminder_settings', {
        'cylinder_id': 'c2',
        'recheck_enabled': 0,
        'recheck_days': 14,
        'notification_id': 77,
        'updated_at_ms': 2,
      }),
      throwsA(isA<DatabaseException>()),
    );
  });
}
