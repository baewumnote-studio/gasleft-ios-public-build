import 'package:flutter/foundation.dart';

import 'release_config_validator.dart';

abstract final class AppConfig {
  static const String appName = 'GasLeft';
  static const String googleTestInterstitialIos =
      'ca-app-pub-3940256099942544/4411468910';
  // TestFlight also runs in release mode. Only an explicit build flag enables
  // Google's sample ads there; ordinary release builds keep publisher IDs.
  static const bool useTestAds = bool.fromEnvironment('ADMOB_USE_TEST_ADS');
  static const String productionInterstitialIos = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_IOS',
  );

  static String get interstitialAdUnitId {
    if (kReleaseMode && !useTestAds) return productionInterstitialIos;
    return googleTestInterstitialIos;
  }

  static bool get hasAdUnitForCurrentBuild => interstitialAdUnitId.isNotEmpty;

  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
  );
  static const String supportEmail = String.fromEnvironment('SUPPORT_EMAIL');

  static List<String> get releaseConfigurationIssues =>
      ReleaseConfigValidator.issues(
        interstitialAdUnitId: useTestAds
            ? googleTestInterstitialIos
            : productionInterstitialIos,
        privacyPolicyUrl: privacyPolicyUrl,
        supportEmail: supportEmail,
        allowTestAds: useTestAds,
      );

  static void validateReleaseConfiguration() {
    if (!kReleaseMode) return;
    final issues = releaseConfigurationIssues;
    if (issues.isNotEmpty) {
      throw StateError(
        'GasLeft release configuration is incomplete: ${issues.join(' | ')}',
      );
    }
  }

  static const int databaseVersion = 3;
  static const String databaseName = 'gasleft.sqlite';
  static const int defaultLowThresholdPct = 20;
  static const int defaultRecheckDays = 14;
}
