import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/app_strings.dart';
import 'reminder_date_calculator.dart';

class PendingLocalNotification {
  const PendingLocalNotification({required this.id, this.payload});

  final int id;
  final String? payload;
}

class NotificationService {
  NotificationService({AppStrings strings = AppStrings.english})
    // Keep the public strings parameter and private catalog storage.
    // ignore: prefer_initializing_formals
    : _strings = strings;

  final AppStrings _strings;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  void Function(String payload)? onPayload;
  String? _initialPayload;
  bool _initialized = false;
  bool _timezoneReady = false;
  Future<void>? _initializeInFlight;

  /// Payload that launched a fully terminated app. This must be consumed by
  /// bootstrap after onboarding state is known because the normal notification
  /// response callback is not used for cold-start navigation.
  String? takeInitialPayload() {
    final value = _initialPayload;
    _initialPayload = null;
    return value;
  }

  /// Initializes the notification plugin at most once per successful app run.
  /// Concurrent callers share the same future, while a failed attempt can be
  /// retried later from bootstrap or a user action.
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    final existing = _initializeInFlight;
    if (existing != null) return existing;

    final future = _initializeInternal();
    _initializeInFlight = future;
    return future.whenComplete(() {
      _initializeInFlight = null;
    });
  }

  Future<void> _initializeInternal() async {
    tzdata.initializeTimeZones();
    await refreshLocalTimezone();

    const settings = InitializationSettings(
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          onPayload?.call(payload);
        }
      },
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final payload = launchDetails?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        _initialPayload = payload;
      }
    }
    _initialized = true;
  }

  /// Refreshes tz.local after a device timezone change while the app remains
  /// installed/running. A failure is non-fatal for the core app, but reminders
  /// are deliberately not scheduled against UTC as a silent fallback.
  Future<bool> refreshLocalTimezone() async {
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
      _timezoneReady = true;
      return true;
    } catch (_) {
      _timezoneReady = false;
      return false;
    }
  }

  Future<void> _ensureReady() async {
    await initialize();
  }

  Future<bool> requestPermission() async {
    await _ensureReady();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(
          alert: true,
          badge: false,
          sound: true,
        ) ??
        false;
  }

  /// Returns the current iOS notification authorization state without
  /// prompting. `null` means the status could not be read.
  Future<bool?> notificationsEnabled() async {
    try {
      await _ensureReady();
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final options = await ios?.checkPermissions();
      return options?.isEnabled;
    } catch (_) {
      return null;
    }
  }

  Future<void> cancel(int notificationId) async {
    await _ensureReady();
    await _plugin.cancel(id: notificationId);
  }

  Future<List<PendingLocalNotification>> pendingNotifications() async {
    await _ensureReady();
    final requests = await _plugin.pendingNotificationRequests();
    return requests
        .map(
          (request) => PendingLocalNotification(
            id: request.id,
            payload: request.payload,
          ),
        )
        .toList(growable: false);
  }

  Future<bool> openNotificationSettings() async {
    await _ensureReady();
    return await _plugin.openAppNotificationSettings() ?? false;
  }

  Future<bool> scheduleRecheck({
    required int notificationId,
    required String cylinderId,
    required String cylinderName,
    required int measuredAtEpochMs,
    required int days,
  }) async {
    await _ensureReady();
    if (!_timezoneReady && !await refreshLocalTimezone()) {
      throw StateError(
        'The device timezone could not be resolved. Recheck reminder was not scheduled.',
      );
    }

    final dueDate = ReminderDateCalculator.dueCalendarDate(
      measuredAtEpochMs: measuredAtEpochMs,
      days: days,
    );
    final scheduled = tz.TZDateTime(
      tz.local,
      dueDate.year,
      dueDate.month,
      dueDate.day,
      10,
    );
    final now = tz.TZDateTime.now(tz.local);
    if (!scheduled.isAfter(now)) {
      // Recheck reminders are one-shot per measurement. Once the target time
      // has passed, launch/resume repair must not keep re-arming a notification
      // one minute into the future. A new weight reading creates the next due
      // date instead.
      return false;
    }

    await _plugin.zonedSchedule(
      id: notificationId,
      title: _strings.text('notificationRecheckTitle', {'name': cylinderName}),
      body: _strings.text('notificationRecheckBody', {'days': days}),
      scheduledDate: scheduled,
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'cylinder:$cylinderId',
    );
    return true;
  }
}
