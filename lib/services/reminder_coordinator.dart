import 'dart:async';

import '../data/gas_repository.dart';
import '../domain/models/settings_models.dart';
import 'notification_service.dart';
import 'notification_payload.dart';

class ReminderCoordinator {
  ReminderCoordinator(this._repository, this._notifications);

  final GasRepository _repository;
  final NotificationService _notifications;

  // Local-notification mutations must be serialized. App-resume repair can run
  // at the same time as a user toggles or changes a reminder; without a queue,
  // an older schedule operation could finish last and overwrite the newer one
  // because iOS replaces requests by notification ID.
  Future<void> _operationTail = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<bool> enable({required String cylinderId, required int days}) =>
      _serialized(() => _enable(cylinderId: cylinderId, days: days));

  Future<bool> _enable({required String cylinderId, required int days}) async {
    // Do not rely on the UI switch being disabled. A reminder has no honest
    // schedule until the current physical-cylinder revision has a reading, so
    // enforce that invariant in the domain service before prompting iOS.
    final cylinder = await _repository.getCylinder(cylinderId);
    if (cylinder == null) return false;
    final latest = await _repository.getLatestReadingForRevision(
      cylinderId,
      cylinder.currentRevision,
    );
    if (latest == null) return false;

    final granted = await _notifications.requestPermission();
    await _markPermissionAsked();

    final current = await _repository.getReminder(cylinderId);
    final updated = ReminderSettings(
      cylinderId: current.cylinderId,
      recheckEnabled: granted,
      recheckDays: days.clamp(1, 90).toInt(),
      notificationId: current.notificationId,
      updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _repository.saveReminder(updated);

    if (!granted) {
      // Permission denial is not a scheduling failure. Persist the disabled
      // state and remove any stale request if possible.
      try {
        await _notifications.cancel(current.notificationId);
      } catch (_) {
        // iOS permission remains the final authority; stale local requests
        // cannot surface while notification permission is denied.
      }
      return false;
    }

    try {
      await _sync(cylinderId);
      return true;
    } catch (_) {
      // Avoid showing a switch as enabled when no notification could be
      // scheduled. Restore the pre-change state and let the UI report failure.
      await _repository.saveReminder(current);
      try {
        await _sync(cylinderId);
      } catch (_) {
        // Best-effort restoration; startup synchronization retries later.
      }
      rethrow;
    }
  }

  Future<void> _markPermissionAsked() async {
    final settings = await _repository.getAppSettings();
    if (settings.notificationPermissionAsked) return;
    // Partial update avoids racing with an appearance/default-unit change.
    await _repository.markNotificationPermissionAsked();
  }

  Future<void> disable(String cylinderId) =>
      _serialized(() => _disable(cylinderId));

  Future<void> _disable(String cylinderId) async {
    final current = await _repository.getReminder(cylinderId);
    final disabled = ReminderSettings(
      cylinderId: current.cylinderId,
      recheckEnabled: false,
      recheckDays: current.recheckDays,
      notificationId: current.notificationId,
      updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _repository.saveReminder(disabled);

    try {
      await _notifications.cancel(current.notificationId);
    } catch (_) {
      // Keep persisted/UI state consistent with the still-pending request.
      await _repository.saveReminder(current);
      rethrow;
    }
  }

  Future<void> changeDays(String cylinderId, int days) =>
      _serialized(() => _changeDays(cylinderId, days));

  Future<void> _changeDays(String cylinderId, int days) async {
    final current = await _repository.getReminder(cylinderId);
    final updated = ReminderSettings(
      cylinderId: current.cylinderId,
      recheckEnabled: current.recheckEnabled,
      recheckDays: days.clamp(1, 90).toInt(),
      notificationId: current.notificationId,
      updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _repository.saveReminder(updated);

    try {
      await _sync(cylinderId);
    } catch (_) {
      // A failed reschedule must not leave the UI saying the new interval is
      // active when the old notification remains. Restore and retry the old
      // schedule best-effort, then report failure to the caller.
      await _repository.saveReminder(current);
      try {
        await _sync(cylinderId);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> sync(String cylinderId) => _serialized(() => _sync(cylinderId));

  Future<void> _sync(String cylinderId) async {
    final reminder = await _repository.getReminder(cylinderId);
    if (!reminder.recheckEnabled) {
      await _notifications.cancel(reminder.notificationId);
      return;
    }

    final cylinder = await _repository.getCylinder(cylinderId);
    if (cylinder == null) {
      await _notifications.cancel(reminder.notificationId);
      return;
    }
    final latest = await _repository.getLatestReadingForRevision(
      cylinderId,
      cylinder.currentRevision,
    );
    if (latest == null) {
      await _notifications.cancel(reminder.notificationId);
      return;
    }

    // iOS replaces a pending UNNotificationRequest when a new request uses the
    // same identifier. Schedule first so a transient timezone/plugin failure
    // leaves the previously valid reminder intact instead of creating a gap.
    final scheduled = await _notifications.scheduleRecheck(
      notificationId: reminder.notificationId,
      cylinderId: cylinder.id,
      cylinderName: cylinder.name,
      measuredAtEpochMs: latest.measuredAtEpochMs,
      days: reminder.recheckDays,
    );
    if (!scheduled) {
      // The due time has already passed, so this measurement no longer owns a
      // future reminder. Remove any older request with the same identifier.
      await _notifications.cancel(reminder.notificationId);
    }
  }

  /// Reconciles every persisted reminder row with iOS and then removes any
  /// GasLeft recheck notification whose cylinder/reminder no longer exists.
  /// This heals failed cancellations after delete/permission/settings changes.
  Future<void> repairAll() => _serialized(_repairAll);

  Future<void> _repairAll() async {
    final reminders = await _repository.listReminders();

    // Preserve the user's in-app reminder preference even when iOS notification
    // permission is turned off in Settings. While permission is explicitly
    // disabled, remove GasLeft's pending OS requests and avoid creating new
    // ones. If the user later re-enables notifications, the next launch/resume
    // repair rebuilds the schedule from the latest current-revision reading.
    final permissionEnabled = await _notifications.notificationsEnabled();
    if (permissionEnabled == false) {
      await _cancelAllKnownAndOrphanRequests(reminders);
      return;
    }

    final failedOnce = <String>[];
    for (final reminder in reminders) {
      try {
        // `sync` cancels disabled/stale/no-reading requests. Enabled future
        // reminders are replaced by scheduling the same notification ID.
        await _sync(reminder.cylinderId);
      } catch (_) {
        // Do not let one cylinder block all others. Keep one immediate retry for
        // transient plugin/timezone errors before deferring to the next resume.
        failedOnce.add(reminder.cylinderId);
      }
    }

    for (final cylinderId in failedOnce) {
      try {
        await _sync(cylinderId);
      } catch (_) {
        // Best effort; next launch/resume or user action retries again.
      }
    }

    try {
      final pending = await _notifications.pendingNotifications();
      final reminderById = <int, ReminderSettings>{
        for (final reminder in reminders) reminder.notificationId: reminder,
      };
      for (final request in pending) {
        final cylinderId = NotificationPayload.cylinderId(request.payload);
        if (cylinderId == null) continue;

        final reminder = reminderById[request.id];
        var shouldCancel =
            reminder == null ||
            reminder.cylinderId != cylinderId ||
            !reminder.recheckEnabled;

        if (!shouldCancel) {
          final cylinder = await _repository.getCylinder(cylinderId);
          if (cylinder == null) {
            shouldCancel = true;
          } else {
            final latest = await _repository.getLatestReadingForRevision(
              cylinderId,
              cylinder.currentRevision,
            );
            // An enabled preference may intentionally survive a replacement or
            // deletion of the latest reading, but there must be no pending OS
            // request until a fresh current-revision reading exists.
            shouldCancel = latest == null;
          }
        }

        if (shouldCancel) {
          try {
            // This is also a second best-effort attempt when the earlier `sync`
            // cancellation failed transiently for a disabled/stale reminder.
            await _notifications.cancel(request.id);
          } catch (_) {
            // Best effort; next launch/resume retries orphan cleanup.
          }
        }
      }
    } catch (_) {
      // Pending-request enumeration is also best effort.
    }
  }

  Future<void> _cancelAllKnownAndOrphanRequests(
    List<ReminderSettings> reminders,
  ) async {
    for (final reminder in reminders) {
      try {
        await _notifications.cancel(reminder.notificationId);
      } catch (_) {
        // Best effort. A later resume retries cleanup.
      }
    }

    try {
      final knownIds = reminders.map((value) => value.notificationId).toSet();
      final pending = await _notifications.pendingNotifications();
      for (final request in pending) {
        if (knownIds.contains(request.id)) continue;
        if (NotificationPayload.cylinderId(request.payload) == null) continue;
        try {
          await _notifications.cancel(request.id);
        } catch (_) {
          // Best effort. A later resume retries orphan cleanup.
        }
      }
    } catch (_) {
      // Enumeration is best effort.
    }
  }

  Future<void> cancelForCylinder(String cylinderId) =>
      _serialized(() => _cancelForCylinder(cylinderId));

  Future<void> _cancelForCylinder(String cylinderId) async {
    final reminder = await _repository.getReminder(cylinderId);
    await _notifications.cancel(reminder.notificationId);
  }
}
