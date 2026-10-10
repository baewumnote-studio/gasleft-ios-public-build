import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/gasleft_app.dart';
import 'app/providers.dart';
import 'core/app_config.dart';
import 'data/app_database.dart';
import 'services/consent_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validateReleaseConfiguration();

  // Keep startup lightweight. Database opening and notification initialization
  // are retried from BootstrapScreen, where failures can be surfaced without
  // crashing before the first Flutter frame.
  final database = AppDatabase();
  final notifications = NotificationService();
  final consent = ConsentService();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        notificationServiceProvider.overrideWithValue(notifications),
        consentServiceProvider.overrideWithValue(consent),
      ],
      child: GasLeftApp(notifications: notifications),
    ),
  );
}
