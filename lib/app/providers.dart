import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';
import '../data/gas_repository.dart';
import '../domain/models/settings_models.dart';
import '../domain/models/view_models.dart';
import '../services/ad_service.dart';
import '../services/consent_service.dart';
import '../services/notification_service.dart';
import '../services/reminder_coordinator.dart';

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden'),
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => throw UnimplementedError(
    'notificationServiceProvider must be overridden',
  ),
);

final consentServiceProvider = Provider<ConsentService>(
  (ref) =>
      throw UnimplementedError('consentServiceProvider must be overridden'),
);

final repositoryProvider = Provider<GasRepository>(
  (ref) => GasRepository(ref.watch(databaseProvider)),
);

final reminderCoordinatorProvider = Provider<ReminderCoordinator>(
  (ref) => ReminderCoordinator(
    ref.watch(repositoryProvider),
    ref.watch(notificationServiceProvider),
  ),
);

final adServiceProvider = Provider<AdService>((ref) {
  final service = AdService(
    ref.watch(repositoryProvider),
    ref.watch(consentServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final privacyOptionsRequiredProvider = FutureProvider<bool>((ref) async {
  final consent = ref.watch(consentServiceProvider);
  // UMP consent information is refreshed on every launch. Join the same
  // serialized refresh here so Settings can expose a required privacy-options
  // entry point even before GasLeft is eligible to request its first ad.
  await consent.refreshInfo();
  return consent.privacyOptionsRequired();
});

final appSettingsProvider = FutureProvider<AppSettings>(
  (ref) => ref.watch(repositoryProvider).getAppSettings(),
);

final cylinderSummariesProvider = FutureProvider<List<CylinderSummary>>(
  (ref) => ref.watch(repositoryProvider).listSummaries(),
);

final cylinderDetailProvider =
    FutureProvider.family<CylinderDetailData?, String>(
      (ref, id) => ref.watch(repositoryProvider).getDetail(id),
    );
