import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gasleft/app/gasleft_app.dart';
import 'package:gasleft/app/providers.dart';
import 'package:gasleft/core/enums.dart';
import 'package:gasleft/data/app_database.dart';
import 'package:gasleft/data/gas_repository.dart';
import 'package:gasleft/services/consent_service.dart';
import 'package:gasleft/services/notification_service.dart';

class _FakeNotificationService extends NotificationService {
  @override
  Future<void> initialize() async {}

  @override
  Future<List<PendingLocalNotification>> pendingNotifications() async => [];
  @override
  Future<bool> refreshLocalTimezone() async => true;

  @override
  String? takeInitialPayload() => null;

  @override
  Future<void> cancel(int notificationId) async {}

  @override
  Future<bool?> notificationsEnabled() async => true;
}

class _FakeConsentService extends ConsentService {
  @override
  Future<void> refreshInfo() async {}
  @override
  Future<void> refresh() async {}

  @override
  Future<bool> canRequestAds() async => false;

  @override
  Future<bool> privacyOptionsRequired() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets('adding a later cylinder preserves Home under Add Reading', (
    tester,
  ) async {
    final database = AppDatabase(
      databaseFactoryOverride: databaseFactoryFfiNoIsolate,
      databasePathOverride: inMemoryDatabasePath,
    );
    final repository = GasRepository(database);
    final settings = await repository.getAppSettings();
    await repository.saveAppSettings(
      settings.copyWith(
        onboardingComplete: true,
        updatedAtEpochMs: DateTime(2026, 10, 7).millisecondsSinceEpoch,
      ),
    );

    final notifications = _FakeNotificationService();
    final consent = _FakeConsentService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          notificationServiceProvider.overrideWithValue(notifications),
          consentServiceProvider.overrideWithValue(consent),
        ],
        child: GasLeftApp(notifications: notifications),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('My Cylinders'), findsOneWidget);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add Cylinder'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'Camper');
    await tester.enterText(fields.at(1), '9');
    await tester.enterText(fields.at(2), '10.4');
    await tester.scrollUntilVisible(
      find.text('Save'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Add Reading'), findsWidgets);
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('My Cylinders'), findsOneWidget);
    expect(find.text('Camper'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
  });

  testWidgets(
    'first-cylinder reading can be deferred without losing cylinder',
    (tester) async {
      final database = AppDatabase(
        databaseFactoryOverride: databaseFactoryFfiNoIsolate,
        databasePathOverride: inMemoryDatabasePath,
      );
      final notifications = _FakeNotificationService();
      final consent = _FakeConsentService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            notificationServiceProvider.overrideWithValue(notifications),
            consentServiceProvider.overrideWithValue(consent),
          ],
          child: GasLeftApp(notifications: notifications),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No sensor required.'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add my first cylinder'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(3));
      await tester.enterText(fields.at(0), 'BBQ Tank');
      await tester.enterText(fields.at(1), '9');
      await tester.enterText(fields.at(2), '10.4');
      await tester.scrollUntilVisible(
        find.text('Save'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Measure later'), findsOneWidget);
      await tester.tap(find.byTooltip('Measure later'));
      await tester.pumpAndSettle();

      expect(find.text('My Cylinders'), findsOneWidget);
      expect(find.text('BBQ Tank'), findsOneWidget);
      expect(find.text('Add your first reading'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await database.close();
    },
  );

  testWidgets('warm notification opens an existing cylinder reading screen', (
    tester,
  ) async {
    final database = AppDatabase(
      databaseFactoryOverride: databaseFactoryFfiNoIsolate,
      databasePathOverride: inMemoryDatabasePath,
    );
    final repository = GasRepository(database);
    final settings = await repository.getAppSettings();
    await repository.saveAppSettings(
      settings.copyWith(
        onboardingComplete: true,
        updatedAtEpochMs: DateTime(2026, 10, 7).millisecondsSinceEpoch,
      ),
    );
    final id = await repository.createCylinder(
      name: 'Camper',
      useCase: CylinderUseCase.rvCaravan,
      preferredUnit: MassUnit.kg,
      tareGrams: 10000,
      capacityGrams: 9000,
      lowThresholdPct: 20,
    );

    final notifications = _FakeNotificationService();
    final consent = _FakeConsentService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          notificationServiceProvider.overrideWithValue(notifications),
          consentServiceProvider.overrideWithValue(consent),
        ],
        child: GasLeftApp(notifications: notifications),
      ),
    );
    await tester.pumpAndSettle();

    notifications.onPayload?.call('cylinder:$id');
    await tester.pumpAndSettle();
    expect(find.text('Add Reading'), findsWidgets);
    expect(find.text('Camper'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
  });

  testWidgets('warm stale notification falls back to Home', (tester) async {
    final database = AppDatabase(
      databaseFactoryOverride: databaseFactoryFfiNoIsolate,
      databasePathOverride: inMemoryDatabasePath,
    );
    final repository = GasRepository(database);
    final settings = await repository.getAppSettings();
    await repository.saveAppSettings(
      settings.copyWith(
        onboardingComplete: true,
        updatedAtEpochMs: DateTime(2026, 10, 7).millisecondsSinceEpoch,
      ),
    );

    final notifications = _FakeNotificationService();
    final consent = _FakeConsentService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          notificationServiceProvider.overrideWithValue(notifications),
          consentServiceProvider.overrideWithValue(consent),
        ],
        child: GasLeftApp(notifications: notifications),
      ),
    );
    await tester.pumpAndSettle();

    notifications.onPayload?.call('cylinder:deleted-id');
    await tester.pumpAndSettle();
    expect(find.text('My Cylinders'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
  });

  testWidgets('recheck reminder cannot be enabled before the first reading', (
    tester,
  ) async {
    final database = AppDatabase(
      databaseFactoryOverride: databaseFactoryFfiNoIsolate,
      databasePathOverride: inMemoryDatabasePath,
    );
    final repository = GasRepository(database);
    final settings = await repository.getAppSettings();
    await repository.saveAppSettings(
      settings.copyWith(
        onboardingComplete: true,
        updatedAtEpochMs: DateTime(2026, 10, 7).millisecondsSinceEpoch,
      ),
    );
    await repository.createCylinder(
      name: 'BBQ',
      useCase: CylinderUseCase.bbq,
      preferredUnit: MassUnit.kg,
      tareGrams: 10000,
      capacityGrams: 9000,
      lowThresholdPct: 20,
    );

    final notifications = _FakeNotificationService();
    final consent = _FakeConsentService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          notificationServiceProvider.overrideWithValue(notifications),
          consentServiceProvider.overrideWithValue(consent),
        ],
        child: GasLeftApp(notifications: notifications),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('BBQ'));
    await tester.pumpAndSettle();

    expect(
      find.text('Add a reading before turning on recheck reminders.'),
      findsOneWidget,
    );
    final reminderSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Recheck reminder'),
    );
    expect(reminderSwitch.value, isFalse);
    expect(reminderSwitch.onChanged, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
  });
}
