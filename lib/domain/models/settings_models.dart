import '../../core/enums.dart';

class ReminderSettings {
  const ReminderSettings({
    required this.cylinderId,
    required this.recheckEnabled,
    required this.recheckDays,
    required this.notificationId,
    required this.updatedAtEpochMs,
  });

  final String cylinderId;
  final bool recheckEnabled;
  final int recheckDays;
  final int notificationId;
  final int updatedAtEpochMs;

  factory ReminderSettings.fromMap(Map<String, Object?> map) =>
      ReminderSettings(
        cylinderId: map['cylinder_id']! as String,
        recheckEnabled: (map['recheck_enabled']! as int) == 1,
        recheckDays: map['recheck_days']! as int,
        notificationId: map['notification_id']! as int,
        updatedAtEpochMs: map['updated_at_ms']! as int,
      );

  Map<String, Object?> toMap() => {
    'cylinder_id': cylinderId,
    'recheck_enabled': recheckEnabled ? 1 : 0,
    'recheck_days': recheckDays,
    'notification_id': notificationId,
    'updated_at_ms': updatedAtEpochMs,
  };
}

class AppSettings {
  const AppSettings({
    required this.themeMode,
    required this.defaultUnit,
    required this.onboardingComplete,
    required this.notificationPermissionAsked,
    required this.createdAtEpochMs,
    required this.updatedAtEpochMs,
  });

  final AppThemeMode themeMode;
  final MassUnit defaultUnit;
  final bool onboardingComplete;
  final bool notificationPermissionAsked;
  final int createdAtEpochMs;
  final int updatedAtEpochMs;

  factory AppSettings.fromMap(Map<String, Object?> map) => AppSettings(
    themeMode: AppThemeMode.fromDb(map['theme_mode']! as String),
    defaultUnit: MassUnit.fromDb(map['default_unit']! as String),
    onboardingComplete: (map['onboarding_complete']! as int) == 1,
    notificationPermissionAsked:
        (map['notification_permission_asked']! as int) == 1,
    createdAtEpochMs: map['created_at_ms']! as int,
    updatedAtEpochMs: map['updated_at_ms']! as int,
  );

  Map<String, Object?> toMap() => {
    'id': 1,
    'theme_mode': themeMode.name,
    'default_unit': defaultUnit.name,
    'onboarding_complete': onboardingComplete ? 1 : 0,
    'notification_permission_asked': notificationPermissionAsked ? 1 : 0,
    'created_at_ms': createdAtEpochMs,
    'updated_at_ms': updatedAtEpochMs,
  };

  AppSettings copyWith({
    AppThemeMode? themeMode,
    MassUnit? defaultUnit,
    bool? onboardingComplete,
    bool? notificationPermissionAsked,
    int? updatedAtEpochMs,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      defaultUnit: defaultUnit ?? this.defaultUnit,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      notificationPermissionAsked:
          notificationPermissionAsked ?? this.notificationPermissionAsked,
      createdAtEpochMs: createdAtEpochMs,
      updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
    );
  }
}

class AdState {
  const AdState({
    required this.completedReadingCount,
    required this.interstitialImpressionCount,
    required this.dailyInterstitialCount,
    required this.firstSessionCompleted,
    required this.lastEligibleReadingCount,
    this.lastInterstitialAtEpochMs,
    this.lastInterstitialDayKey,
  });

  final int completedReadingCount;
  final int interstitialImpressionCount;
  final int? lastInterstitialAtEpochMs;
  final String? lastInterstitialDayKey;
  final int dailyInterstitialCount;
  final bool firstSessionCompleted;
  final int lastEligibleReadingCount;

  factory AdState.fromMap(Map<String, Object?> map) => AdState(
    completedReadingCount: map['completed_reading_count']! as int,
    interstitialImpressionCount: map['interstitial_impression_count']! as int,
    lastInterstitialAtEpochMs: map['last_interstitial_at_ms'] as int?,
    lastInterstitialDayKey: map['last_interstitial_day_key'] as String?,
    dailyInterstitialCount: map['daily_interstitial_count']! as int,
    firstSessionCompleted: (map['first_session_completed']! as int) == 1,
    lastEligibleReadingCount: map['last_eligible_reading_count']! as int,
  );

  Map<String, Object?> toMap() => {
    'id': 1,
    'completed_reading_count': completedReadingCount,
    'interstitial_impression_count': interstitialImpressionCount,
    'last_interstitial_at_ms': lastInterstitialAtEpochMs,
    'last_interstitial_day_key': lastInterstitialDayKey,
    'daily_interstitial_count': dailyInterstitialCount,
    'first_session_completed': firstSessionCompleted ? 1 : 0,
    'last_eligible_reading_count': lastEligibleReadingCount,
  };

  AdState copyWith({
    int? completedReadingCount,
    int? interstitialImpressionCount,
    int? lastInterstitialAtEpochMs,
    String? lastInterstitialDayKey,
    int? dailyInterstitialCount,
    bool? firstSessionCompleted,
    int? lastEligibleReadingCount,
  }) {
    return AdState(
      completedReadingCount:
          completedReadingCount ?? this.completedReadingCount,
      interstitialImpressionCount:
          interstitialImpressionCount ?? this.interstitialImpressionCount,
      lastInterstitialAtEpochMs:
          lastInterstitialAtEpochMs ?? this.lastInterstitialAtEpochMs,
      lastInterstitialDayKey:
          lastInterstitialDayKey ?? this.lastInterstitialDayKey,
      dailyInterstitialCount:
          dailyInterstitialCount ?? this.dailyInterstitialCount,
      firstSessionCompleted:
          firstSessionCompleted ?? this.firstSessionCompleted,
      lastEligibleReadingCount:
          lastEligibleReadingCount ?? this.lastEligibleReadingCount,
    );
  }
}
