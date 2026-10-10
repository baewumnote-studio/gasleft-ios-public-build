import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gasleft/core/enums.dart';
import 'package:gasleft/data/app_database.dart';
import 'package:gasleft/data/gas_repository.dart';
import 'package:gasleft/domain/models/settings_models.dart';

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

  Future<String> seedCylinder(String name) {
    return repository.createCylinder(
      name: name,
      useCase: CylinderUseCase.bbq,
      preferredUnit: MassUnit.kg,
      tareGrams: 10000,
      capacityGrams: 9000,
      lowThresholdPct: 20,
    );
  }

  test('missing legacy reminder row is recreated safely', () async {
    final id = await seedCylinder('BBQ');
    final db = await database.db;
    await db.delete(
      'reminder_settings',
      where: 'cylinder_id = ?',
      whereArgs: [id],
    );

    final reminder = await repository.getReminder(id);
    expect(reminder.cylinderId, id);
    expect(reminder.recheckEnabled, isFalse);
    expect(reminder.recheckDays, 14);

    final rows = await db.query(
      'reminder_settings',
      where: 'cylinder_id = ?',
      whereArgs: [id],
    );
    expect(rows, hasLength(1));
  });

  test('cannot recreate a reminder for a missing cylinder', () async {
    await expectLater(
      repository.getReminder('missing-cylinder'),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'partial app setting updates do not overwrite the other setting',
    () async {
      await repository.updateDefaultUnit(MassUnit.lb);
      await repository.updateThemeMode(AppThemeMode.dark);

      var settings = await repository.getAppSettings();
      expect(settings.defaultUnit, MassUnit.lb);
      expect(settings.themeMode, AppThemeMode.dark);
      expect(settings.notificationPermissionAsked, isFalse);

      await repository.markNotificationPermissionAsked();
      settings = await repository.getAppSettings();
      expect(settings.defaultUnit, MassUnit.lb);
      expect(settings.themeMode, AppThemeMode.dark);
      expect(settings.notificationPermissionAsked, isTrue);
    },
  );

  test('rapid sequential creates receive unique stable sort orders', () async {
    await seedCylinder('One');
    await seedCylinder('Two');
    await seedCylinder('Three');

    final cylinders = await repository.listCylinders();
    expect(cylinders.map((c) => c.sortOrder).toList(), [0, 1, 2]);
  });

  test(
    'saveReminder updates the existing row without duplicating it',
    () async {
      final id = await seedCylinder('Reminder');
      final current = await repository.getReminder(id);
      final updated = ReminderSettings(
        cylinderId: id,
        recheckEnabled: true,
        recheckDays: 21,
        notificationId: current.notificationId,
        updatedAtEpochMs: DateTime(2026, 10, 7).millisecondsSinceEpoch,
      );

      await repository.saveReminder(updated);

      final db = await database.db;
      final rows = await db.query(
        'reminder_settings',
        where: 'cylinder_id = ?',
        whereArgs: [id],
      );
      expect(rows, hasLength(1));
      final saved = await repository.getReminder(id);
      expect(saved.recheckEnabled, isTrue);
      expect(saved.recheckDays, 21);
      expect(saved.notificationId, current.notificationId);
    },
  );

  test(
    'saveReminder uniqueness failure does not replace another cylinder row',
    () async {
      final firstId = await seedCylinder('First');
      final secondId = await seedCylinder('Second');
      final first = await repository.getReminder(firstId);
      final second = await repository.getReminder(secondId);

      final conflicting = ReminderSettings(
        cylinderId: secondId,
        recheckEnabled: true,
        recheckDays: 30,
        notificationId: first.notificationId,
        updatedAtEpochMs: DateTime(2026, 10, 7).millisecondsSinceEpoch,
      );

      await expectLater(
        repository.saveReminder(conflicting),
        throwsA(anything),
      );

      final firstAfter = await repository.getReminder(firstId);
      final secondAfter = await repository.getReminder(secondId);
      expect(firstAfter.notificationId, first.notificationId);
      expect(secondAfter.notificationId, second.notificationId);
      expect(secondAfter.recheckEnabled, isFalse);
    },
  );

  test(
    'markFirstSessionCompleted changes only the first-session column',
    () async {
      final db = await database.db;
      await db.update('ad_state', {
        'completed_reading_count': 8,
        'interstitial_impression_count': 2,
        'daily_interstitial_count': 1,
        'last_eligible_reading_count': 4,
      }, where: 'id = 1');

      await repository.markFirstSessionCompleted();
      await repository.markFirstSessionCompleted();

      final rows = await db.query('ad_state', where: 'id = 1', limit: 1);
      final row = rows.single;
      expect(row['first_session_completed'], 1);
      expect(row['completed_reading_count'], 8);
      expect(row['interstitial_impression_count'], 2);
      expect(row['daily_interstitial_count'], 1);
      expect(row['last_eligible_reading_count'], 4);
    },
  );

  test('onboarding completion updates only its own settings columns', () async {
    final db = await database.db;
    await repository.updateDefaultUnit(MassUnit.lb);
    await repository.updateThemeMode(AppThemeMode.dark);
    await repository.markNotificationPermissionAsked();

    await repository.markOnboardingComplete();
    await repository.markOnboardingComplete();

    final settings = await repository.getAppSettings();
    expect(settings.onboardingComplete, isTrue);
    expect(settings.defaultUnit, MassUnit.lb);
    expect(settings.themeMode, AppThemeMode.dark);
    expect(settings.notificationPermissionAsked, isTrue);

    final rows = await db.query('app_settings', where: 'id = 1', limit: 1);
    expect(rows.single['onboarding_complete'], 1);
  });

  test(
    'interstitial impression accounting preserves newer reading counters',
    () async {
      final db = await database.db;
      await db.update('ad_state', {
        'completed_reading_count': 8,
        'interstitial_impression_count': 2,
        'daily_interstitial_count': 1,
        'last_interstitial_day_key': '2026-10-07',
        'last_eligible_reading_count': 4,
      }, where: 'id = 1');

      await repository.recordInterstitialImpression(
        atEpochMs: DateTime(2026, 10, 7, 12).millisecondsSinceEpoch,
        dayKey: '2026-10-07',
      );

      var state = await repository.getAdState();
      expect(state.completedReadingCount, 8);
      expect(state.interstitialImpressionCount, 3);
      expect(state.dailyInterstitialCount, 2);
      expect(state.lastEligibleReadingCount, 8);

      await repository.recordInterstitialImpression(
        atEpochMs: DateTime(2026, 10, 8, 12).millisecondsSinceEpoch,
        dayKey: '2026-10-08',
      );

      state = await repository.getAdState();
      expect(state.completedReadingCount, 8);
      expect(state.interstitialImpressionCount, 4);
      expect(state.dailyInterstitialCount, 1);
      expect(state.lastInterstitialDayKey, '2026-10-08');
      expect(state.lastEligibleReadingCount, 8);
    },
  );

  test(
    'missing app settings singleton is recreated with safe defaults',
    () async {
      final db = await database.db;
      await db.delete('app_settings', where: 'id = 1');

      final settings = await repository.getAppSettings();

      expect(settings.themeMode, AppThemeMode.system);
      expect(settings.defaultUnit, MassUnit.kg);
      expect(settings.onboardingComplete, isFalse);
      expect(settings.notificationPermissionAsked, isFalse);
      final rows = await db.query('app_settings', where: 'id = 1');
      expect(rows, hasLength(1));
    },
  );

  test(
    'missing ad-state singleton is recreated without blocking the app',
    () async {
      final db = await database.db;
      await db.delete('ad_state', where: 'id = 1');

      final state = await repository.getAdState();

      expect(state.completedReadingCount, 0);
      expect(state.interstitialImpressionCount, 0);
      expect(state.dailyInterstitialCount, 0);
      expect(state.firstSessionCompleted, isFalse);
      expect(state.lastEligibleReadingCount, 0);
      final rows = await db.query('ad_state', where: 'id = 1');
      expect(rows, hasLength(1));
    },
  );

  test(
    'settings recovery infers completed onboarding from existing cylinder data',
    () async {
      final id = await repository.createCylinder(
        name: 'Recovered camper',
        useCase: CylinderUseCase.camping,
        preferredUnit: MassUnit.lb,
        tareGrams: 8000,
        capacityGrams: 9000,
        lowThresholdPct: 20,
      );
      expect(id, isNotEmpty);
      final db = await database.db;
      await db.delete('app_settings', where: 'id = 1');

      final settings = await repository.getAppSettings();

      expect(settings.onboardingComplete, isTrue);
      expect(settings.defaultUnit, MassUnit.lb);
      expect(settings.themeMode, AppThemeMode.system);
    },
  );
}
