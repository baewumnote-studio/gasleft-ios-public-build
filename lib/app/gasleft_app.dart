import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/app_strings.dart';
import '../core/enums.dart';
import '../core/theme/app_theme.dart';
import '../services/notification_payload.dart';
import '../services/notification_service.dart';
import 'app_router.dart';
import 'providers.dart';

class GasLeftApp extends ConsumerStatefulWidget {
  const GasLeftApp({super.key, required this.notifications});

  final NotificationService notifications;

  @override
  ConsumerState<GasLeftApp> createState() => _GasLeftAppState();
}

class _GasLeftAppState extends ConsumerState<GasLeftApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = buildRouter();
    widget.notifications.onPayload = (payload) {
      unawaited(_openNotificationPayload(payload));
    };
  }

  Future<void> _openNotificationPayload(String payload) async {
    final id = NotificationPayload.cylinderId(payload);
    if (id == null) return;
    try {
      final exists = await ref.read(repositoryProvider).getCylinder(id) != null;
      if (!mounted) return;
      _router.go(exists ? '/cylinder/$id/read' : '/home');
    } catch (_) {
      if (mounted) _router.go('/home');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.notifications.onPayload = null;
    _router.dispose();
    super.dispose();
  }

  bool _resumeRepairRunning = false;
  bool _resumeRepairRequested = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumeRepairRequested = true;
      unawaited(_drainResumeRepairs());
    }
  }

  Future<void> _drainResumeRepairs() async {
    if (_resumeRepairRunning) return;
    _resumeRepairRunning = true;
    final container = ref.container;
    try {
      while (_resumeRepairRequested && mounted) {
        _resumeRepairRequested = false;
        try {
          await widget.notifications.refreshLocalTimezone();
          if (!mounted) break;
          await container.read(reminderCoordinatorProvider).repairAll();
        } catch (_) {
          // Resume repair is best-effort and must never interfere with
          // navigation. A later resume requests another pass.
        }
      }
    } finally {
      _resumeRepairRunning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final themeMode = settingsAsync.value?.themeMode ?? AppThemeMode.system;

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => context.strings.appName,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppStrings.supportedLocales,
      routerConfig: _router,
    );
  }
}
