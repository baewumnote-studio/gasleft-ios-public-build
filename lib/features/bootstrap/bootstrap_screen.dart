import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/app_strings.dart';
import '../../core/enums.dart';
import '../../services/notification_payload.dart';

class BootstrapScreen extends ConsumerStatefulWidget {
  const BootstrapScreen({super.key});

  @override
  ConsumerState<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends ConsumerState<BootstrapScreen> {
  bool _started = false;
  bool _bootstrapRunning = false;
  Object? _bootstrapError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_bootstrap());
    }
  }

  Future<void> _bootstrap() async {
    if (_bootstrapRunning) return;
    _bootstrapRunning = true;
    final container = ref.container;
    try {
      // Notification setup is useful for cold-start deep links, but a plugin
      // failure must not prevent the offline calculator from opening.
      try {
        await container.read(notificationServiceProvider).initialize();
      } catch (_) {}

      // Current Google UMP guidance recommends refreshing consent info on
      // every app launch. This call does not present a form; it only refreshes
      // requirement/status information. Advertising remains optional and
      // fully deferred by AdService.
      unawaited(container.read(consentServiceProvider).refreshInfo());

      final repo = container.read(repositoryProvider);
      var settings = await repo.getAppSettings();
      container.invalidate(appSettingsProvider);

      if (!settings.onboardingComplete) {
        final country = PlatformDispatcher.instance.locale.countryCode;
        final desired = country == 'US' ? MassUnit.lb : MassUnit.kg;
        if (settings.defaultUnit != desired) {
          await repo.updateDefaultUnit(desired);
          settings = settings.copyWith(defaultUnit: desired);
          container.invalidate(appSettingsProvider);
        }
      } else {
        await repo.markFirstSessionCompleted();
        // Rebuild local reminder schedules on launch so timezone changes and
        // physical-cylinder revisions cannot leave stale pending notifications.
        unawaited(_syncRemindersSafely(container));
        // No consent form or ad SDK work during the first onboarding session.
        // From the next launch onward, any required consent form may be
        // gathered before an ad request once the reading threshold is met.
        unawaited(container.read(adServiceProvider).bootstrap());
      }

      if (!mounted) return;
      if (!settings.onboardingComplete) {
        context.go('/onboarding');
        return;
      }

      final payload = container
          .read(notificationServiceProvider)
          .takeInitialPayload();
      final cylinderId = NotificationPayload.cylinderId(payload);
      if (cylinderId != null && await repo.getCylinder(cylinderId) != null) {
        if (mounted) context.go('/cylinder/$cylinderId/read');
        return;
      }

      if (mounted) context.go('/home');
    } catch (error) {
      if (mounted) setState(() => _bootstrapError = error);
    } finally {
      _bootstrapRunning = false;
    }
  }

  Future<void> _syncRemindersSafely(ProviderContainer container) async {
    try {
      await container.read(reminderCoordinatorProvider).repairAll();
    } catch (_) {
      // Reminder repair is best-effort and must never block app launch.
    }
  }

  Future<void> _retry() async {
    if (!mounted) return;
    setState(() => _bootstrapError = null);
    await _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    if (_bootstrapError != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 14),
                  Text(
                    strings.text('bootstrapErrorTitle'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.text('bootstrapErrorBody'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _retry,
                    child: Text(strings.text('tryAgainAction')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
