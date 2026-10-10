// Run with the beta flag and synthetic privacy/support Dart defines. This
// checks the configuration path used by TestFlight, without production ad IDs.
import 'package:flutter_test/flutter_test.dart';
import 'package:gasleft/core/app_config.dart';

void main() {
  test('explicit TestFlight build works without publisher ad IDs', () {
    expect(AppConfig.useTestAds, isTrue);
    expect(AppConfig.productionInterstitialIos, isEmpty);
    expect(AppConfig.interstitialAdUnitId, AppConfig.googleTestInterstitialIos);
    expect(AppConfig.releaseConfigurationIssues, isEmpty);
  });
}
