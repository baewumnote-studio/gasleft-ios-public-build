import 'package:flutter_test/flutter_test.dart';

import 'package:gasleft/core/release_config_validator.dart';

void main() {
  test('valid publisher release values have no issues', () {
    expect(
      ReleaseConfigValidator.issues(
        interstitialAdUnitId: 'ca-app-pub-1234567890123456/1234567890',
        privacyPolicyUrl: 'https://example.com/privacy',
        supportEmail: 'support@example.com',
      ),
      isEmpty,
    );
  });

  test('missing values are all reported', () {
    final issues = ReleaseConfigValidator.issues(
      interstitialAdUnitId: '',
      privacyPolicyUrl: '',
      supportEmail: '',
    );
    expect(issues, hasLength(3));
  });

  test('ordinary release rejects Google sample ads', () {
    expect(
      ReleaseConfigValidator.issues(
        interstitialAdUnitId: 'ca-app-pub-3940256099942544/4411468910',
        privacyPolicyUrl: 'https://example.com/privacy',
        supportEmail: 'support@example.com',
      ).any((issue) => issue.contains('ADMOB_USE_TEST_ADS=true')),
      isTrue,
    );
  });

  test(
    'explicit beta mode accepts test ads and still requires public contacts',
    () {
      const testId = 'ca-app-pub-3940256099942544/4411468910';
      expect(
        ReleaseConfigValidator.issues(
          interstitialAdUnitId: testId,
          privacyPolicyUrl: 'https://example.com/privacy',
          supportEmail: 'support@example.com',
          allowTestAds: true,
        ),
        isEmpty,
      );
      final missingContacts = ReleaseConfigValidator.issues(
        interstitialAdUnitId: testId,
        privacyPolicyUrl: '',
        supportEmail: '',
        allowTestAds: true,
      );
      expect(missingContacts, hasLength(2));
      expect(
        missingContacts.every((issue) => !issue.contains('ADMOB')),
        isTrue,
      );
    },
  );

  test('privacy policy must be https and support email must be plausible', () {
    final issues = ReleaseConfigValidator.issues(
      interstitialAdUnitId: 'ca-app-pub-1234567890123456/1234567890',
      privacyPolicyUrl: 'http://example.com/privacy',
      supportEmail: 'not-an-email',
    );
    expect(issues.any((e) => e.contains('https')), isTrue);
    expect(issues.any((e) => e.contains('email')), isTrue);
  });
}
