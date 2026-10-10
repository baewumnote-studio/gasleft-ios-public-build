import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gasleft/core/enums.dart';
import 'package:gasleft/data/app_database.dart';
import 'package:gasleft/data/gas_repository.dart';
import 'package:gasleft/domain/models/settings_models.dart';
import 'package:gasleft/services/notification_service.dart';
import 'package:gasleft/services/reminder_coordinator.dart';

class FakeNotificationService extends NotificationService {
  bool permissionGranted = true;
  bool? currentPermissionEnabled = true;
  bool throwOnSchedule = false;
  bool throwOnCancel = false;
  bool scheduleReturns = true;
  int cancelFailuresRemaining = 0;
  int requestPermissionCalls = 0;
  int cancelCalls = 0;
  int scheduleCalls = 0;
  int? lastScheduledDays;
  String? lastScheduledCylinderId;
  int? lastScheduledMeasuredAtEpochMs;
  Completer<void>? firstScheduleGate;
  bool _firstScheduleGateConsumed = false;
  final List<int> scheduledDays = <int>[];
  List<PendingLocalNotification> pending = <PendingLocalNotification>[];
  final List<int> cancelledIds = <int>[];

  @override
  Future<bool> requestPermission() async {
    requestPermissionCalls += 1;
    return permissionGranted;
  }

  @override
  Future<bool?> notificationsEnabled() async => currentPermissionEnabled;

  @override
  Future<void> cancel(int notificationId) async {
    cancelCalls += 1;
    cancelledIds.add(notificationId);
    if (cancelFailuresRemaining > 0) {
      cancelFailuresRemaining -= 1;
      throw StateError('cancel failed once');
    }
    if (throwOnCancel) throw StateError('cancel failed');
  }

  @override
  Future<List<PendingLocalNotification>> pendingNotifications() async =>
      pending;

  @override
  Future<bool> scheduleRecheck({
    required int notificationId,
    required String cylinderId,
    required String cylinderName,
    required int measuredAtEpochMs,
    required int days,
  }) async {
    scheduleCalls += 1;
    if (throwOnSchedule) throw StateError('schedule failed');
    if (firstScheduleGate != null && !_firstScheduleGateConsumed) {
      _firstScheduleGateConsumed = true;
      await firstScheduleGate!.future;
    }
    scheduledDays.add(days);
    lastScheduledDays = days;
    lastScheduledCylinderId = cylinderId;
    lastScheduledMeasuredAtEpochMs = measuredAtEpochMs;
    return scheduleReturns;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase database;
  late GasRepository repository;
  late FakeNotificationService notifications;
  late ReminderCoordinator coordinator;

  setUp(() {
    database = AppDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePathOverride: inMemoryDatabasePath,
    );
    repository = GasRepository(database);
    notifications = FakeNotificationService();
    coordinator = ReminderCoordinator(repository, notifications);
  });

  tearDown(() async => database.close());

  Future<String> seedWithReading() async {
    final id = await repository.createCylinder(
      name: 'BBQ',
      useCase: CylinderUseCase.bbq,
      preferredUnit: MassUnit.kg,
      tareGrams: 10000,
      capacityGrams: 9000,
      lowThresholdPct: 20,
    );
    final cylinder = (await repository.getCylinder(id))!;
    await repository.addReading(
      cylinder: cylinder,
      measuredAtEpochMs: DateTime(2026, 10, 7).millisecondsSinceEpoch,
      totalWeightGrams: 15000,
      eventType: ReadingEventType.normal,
      validationFlag: ReadingValidationFlag.normal,
      excludedFromPrediction: false,
    );
    return id;
  }

  test(
    'enable persists permission asked and schedules latest reading',
    () async {
      final id = await seedWithReading();
      final granted = await coordinator.enable(cylinderId: id, days: 14);

      expect(granted, isTrue);
      expect((await repository.getReminder(id)).recheckEnabled, isTrue);
      expect(
        (await repository.getAppSettings()).notificationPermissionAsked,
        isTrue,
      );
      expect(notifications.scheduleCalls, 1);
      expect(notifications.lastScheduledCylinderId, id);
      expect(notifications.lastScheduledDays, 14);
    },
  );

  test('permission denial leaves reminder disabled', () async {
    final id = await seedWithReading();
    notifications.permissionGranted = false;

    final granted = await coordinator.enable(cylinderId: id, days: 14);

    expect(granted, isFalse);
    expect((await repository.getReminder(id)).recheckEnabled, isFalse);
    expect(notifications.scheduleCalls, 0);
  });

  test('schedule failure rolls persisted enable state back', () async {
    final id = await seedWithReading();
    notifications.throwOnSchedule = true;

    await expectLater(
      coordinator.enable(cylinderId: id, days: 14),
      throwsStateError,
    );

    expect((await repository.getReminder(id)).recheckEnabled, isFalse);
  });

  test('disable failure restores previously enabled state', () async {
    final id = await seedWithReading();
    await coordinator.enable(cylinderId: id, days: 14);
    notifications.throwOnCancel = true;

    await expectLater(coordinator.disable(id), throwsStateError);
    expect((await repository.getReminder(id)).recheckEnabled, isTrue);
  });

  test(
    'sync schedules the latest reading from the current physical revision',
    () async {
      final id = await seedWithReading();
      var cylinder = (await repository.getCylinder(id))!;
      await repository.replaceCylinder(
        cylinder: cylinder,
        newTareGrams: 8000,
        newCapacityGrams: 9000,
        unit: MassUnit.kg,
      );
      cylinder = (await repository.getCylinder(id))!;
      final backDated = DateTime(2026, 10, 1).millisecondsSinceEpoch;
      await repository.addReading(
        cylinder: cylinder,
        measuredAtEpochMs: backDated,
        totalWeightGrams: 12000,
        eventType: ReadingEventType.replacement,
        validationFlag: ReadingValidationFlag.normal,
        excludedFromPrediction: false,
      );

      await coordinator.enable(cylinderId: id, days: 14);
      expect(notifications.lastScheduledMeasuredAtEpochMs, backDated);
    },
  );

  test('repairAll cancels a stale request for a disabled reminder', () async {
    final id = await seedWithReading();
    final reminder = await repository.getReminder(id);
    notifications.pending = [
      PendingLocalNotification(
        id: reminder.notificationId,
        payload: 'cylinder:$id',
      ),
    ];

    await coordinator.repairAll();

    expect(notifications.cancelledIds, contains(reminder.notificationId));
    expect(notifications.scheduleCalls, 0);
  });

  test(
    'repairAll cancels an orphan GasLeft notification after cylinder deletion',
    () async {
      final id = await seedWithReading();
      final reminder = await repository.getReminder(id);
      await repository.deleteCylinder(id);
      notifications.pending = [
        PendingLocalNotification(
          id: reminder.notificationId,
          payload: 'cylinder:$id',
        ),
      ];
      notifications.cancelledIds.clear();

      await coordinator.repairAll();

      expect(notifications.cancelledIds, contains(reminder.notificationId));
    },
  );

  test(
    'repairAll retries cleanup after a transient disabled-reminder cancel failure',
    () async {
      final id = await seedWithReading();
      final reminder = await repository.getReminder(id);
      notifications.pending = [
        PendingLocalNotification(
          id: reminder.notificationId,
          payload: 'cylinder:$id',
        ),
      ];
      notifications.cancelFailuresRemaining = 1;

      await coordinator.repairAll();

      expect(notifications.cancelCalls, greaterThanOrEqualTo(2));
      expect(
        notifications.cancelledIds
            .where((value) => value == reminder.notificationId)
            .length,
        greaterThanOrEqualTo(2),
      );
    },
  );

  test(
    'enabled sync does not cancel the old request before replacement scheduling',
    () async {
      final id = await seedWithReading();
      final current = await repository.getReminder(id);
      await repository.saveReminder(
        ReminderSettings(
          cylinderId: current.cylinderId,
          recheckEnabled: true,
          recheckDays: current.recheckDays,
          notificationId: current.notificationId,
          updatedAtEpochMs: DateTime(2026, 10, 7).millisecondsSinceEpoch,
        ),
      );

      await coordinator.sync(id);

      expect(notifications.scheduleCalls, 1);
      expect(notifications.cancelCalls, 0);
      expect(notifications.lastScheduledCylinderId, id);
    },
  );

  test('schedule failure preserves an existing enabled request', () async {
    final id = await seedWithReading();
    final current = await repository.getReminder(id);
    await repository.saveReminder(
      ReminderSettings(
        cylinderId: current.cylinderId,
        recheckEnabled: true,
        recheckDays: current.recheckDays,
        notificationId: current.notificationId,
        updatedAtEpochMs: DateTime(2026, 10, 7).millisecondsSinceEpoch,
      ),
    );
    notifications.throwOnSchedule = true;

    await expectLater(coordinator.sync(id), throwsStateError);

    expect(notifications.cancelCalls, 0);
  });

  test(
    'an overdue enabled reminder cancels the stale pending request',
    () async {
      final id = await seedWithReading();
      final current = await repository.getReminder(id);
      await repository.saveReminder(
        ReminderSettings(
          cylinderId: current.cylinderId,
          recheckEnabled: true,
          recheckDays: current.recheckDays,
          notificationId: current.notificationId,
          updatedAtEpochMs: DateTime(2026, 10, 7).millisecondsSinceEpoch,
        ),
      );
      notifications.scheduleReturns = false;

      await coordinator.sync(id);

      expect(notifications.scheduleCalls, 1);
      expect(notifications.cancelledIds, contains(current.notificationId));
    },
  );

  test(
    'repairAll cancels pending request while enabled reminder waits for a current-revision reading',
    () async {
      final id = await seedWithReading();
      var cylinder = (await repository.getCylinder(id))!;
      final reminder = await repository.getReminder(id);
      await repository.saveReminder(
        ReminderSettings(
          cylinderId: reminder.cylinderId,
          recheckEnabled: true,
          recheckDays: reminder.recheckDays,
          notificationId: reminder.notificationId,
          updatedAtEpochMs: DateTime(2026, 10, 7).millisecondsSinceEpoch,
        ),
      );

      // Replacing the physical cylinder advances the revision but intentionally
      // leaves the reminder preference enabled until a new reading is recorded.
      await repository.replaceCylinder(
        cylinder: cylinder,
        newTareGrams: 8000,
        newCapacityGrams: 9000,
        unit: MassUnit.kg,
      );
      cylinder = (await repository.getCylinder(id))!;
      expect(
        await repository.getLatestReadingForRevision(
          id,
          cylinder.currentRevision,
        ),
        isNull,
      );

      notifications.pending = [
        PendingLocalNotification(
          id: reminder.notificationId,
          payload: 'cylinder:$id',
        ),
      ];
      notifications.cancelledIds.clear();

      await coordinator.repairAll();

      expect(notifications.cancelledIds, contains(reminder.notificationId));
      expect(notifications.scheduleCalls, 0);
    },
  );

  test(
    'enable refuses a cylinder with no current-revision reading before prompting',
    () async {
      final id = await repository.createCylinder(
        name: 'Unused',
        useCase: CylinderUseCase.bbq,
        preferredUnit: MassUnit.kg,
        tareGrams: 10000,
        capacityGrams: 9000,
        lowThresholdPct: 20,
      );

      final enabled = await coordinator.enable(cylinderId: id, days: 14);

      expect(enabled, isFalse);
      expect(notifications.requestPermissionCalls, 0);
      expect(notifications.scheduleCalls, 0);
      expect((await repository.getReminder(id)).recheckEnabled, isFalse);
    },
  );

  test('resume repair and a user interval change are serialized', () async {
    final id = await seedWithReading();
    final reminder = await repository.getReminder(id);
    await repository.saveReminder(
      ReminderSettings(
        cylinderId: id,
        recheckEnabled: true,
        recheckDays: 14,
        notificationId: reminder.notificationId,
        updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    notifications.firstScheduleGate = Completer<void>();
    final repairFuture = coordinator.repairAll();
    // Let repair enter its first schedule call and stop at the fake plugin.
    while (notifications.scheduleCalls == 0) {
      await Future<void>.delayed(Duration.zero);
    }

    final changeFuture = coordinator.changeDays(id, 30);
    await Future<void>.delayed(Duration.zero);
    // changeDays must still be queued rather than launching a second schedule.
    expect(notifications.scheduleCalls, 1);

    notifications.firstScheduleGate!.complete();
    await repairFuture;
    await changeFuture;

    expect(notifications.scheduledDays, [14, 30]);
    expect(notifications.lastScheduledDays, 30);
    expect((await repository.getReminder(id)).recheckDays, 30);
  });

  test(
    'repairAll cancels pending reminders while iOS permission is off but keeps the preference enabled',
    () async {
      final id = await seedWithReading();
      final reminder = await repository.getReminder(id);
      await repository.saveReminder(
        ReminderSettings(
          cylinderId: id,
          recheckEnabled: true,
          recheckDays: 14,
          notificationId: reminder.notificationId,
          updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      notifications.currentPermissionEnabled = false;
      notifications.pending = [
        PendingLocalNotification(
          id: reminder.notificationId,
          payload: 'cylinder:$id',
        ),
      ];

      await coordinator.repairAll();

      expect(notifications.scheduleCalls, 0);
      expect(notifications.cancelledIds, contains(reminder.notificationId));
      expect((await repository.getReminder(id)).recheckEnabled, isTrue);
    },
  );

  test(
    'repairAll rebuilds an enabled reminder after iOS permission is restored',
    () async {
      final id = await seedWithReading();
      final reminder = await repository.getReminder(id);
      await repository.saveReminder(
        ReminderSettings(
          cylinderId: id,
          recheckEnabled: true,
          recheckDays: 14,
          notificationId: reminder.notificationId,
          updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      notifications.currentPermissionEnabled = false;
      await coordinator.repairAll();
      expect(notifications.scheduleCalls, 0);

      notifications.currentPermissionEnabled = true;
      notifications.cancelledIds.clear();
      await coordinator.repairAll();

      expect(notifications.scheduleCalls, 1);
      expect(notifications.lastScheduledCylinderId, id);
      expect((await repository.getReminder(id)).recheckEnabled, isTrue);
    },
  );

  test(
    'unknown iOS permission state does not destroy a valid reminder schedule',
    () async {
      final id = await seedWithReading();
      final reminder = await repository.getReminder(id);
      await repository.saveReminder(
        ReminderSettings(
          cylinderId: id,
          recheckEnabled: true,
          recheckDays: 14,
          notificationId: reminder.notificationId,
          updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      notifications.currentPermissionEnabled = null;

      await coordinator.repairAll();

      expect(notifications.scheduleCalls, 1);
      expect(
        notifications.cancelledIds,
        isNot(contains(reminder.notificationId)),
      );
    },
  );
}
