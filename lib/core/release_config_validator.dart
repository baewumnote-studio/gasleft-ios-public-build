abstract final class ReleaseConfigValidator {
  static List<String> issues({
    required String interstitialAdUnitId,
    required String privacyPolicyUrl,
    required String supportEmail,
    bool allowTestAds = false,
  }) {
    final issues = <String>[];

    final adId = interstitialAdUnitId.trim();
    if (adId.isEmpty) {
      issues.add('ADMOB_INTERSTITIAL_IOS is missing.');
    } else if (!RegExp(r'^ca-app-pub-\d+/\d+$').hasMatch(adId)) {
      issues.add(
        'ADMOB_INTERSTITIAL_IOS does not look like an AdMob ad unit ID.',
      );
    } else if (!allowTestAds &&
        adId.startsWith('ca-app-pub-3940256099942544/')) {
      issues.add('Google test ads require ADMOB_USE_TEST_ADS=true.');
    }

    final privacy = Uri.tryParse(privacyPolicyUrl.trim());
    if (privacyPolicyUrl.trim().isEmpty) {
      issues.add('PRIVACY_POLICY_URL is missing.');
    } else if (privacy == null ||
        privacy.scheme.toLowerCase() != 'https' ||
        privacy.host.isEmpty) {
      issues.add('PRIVACY_POLICY_URL must be a valid https URL.');
    }

    final email = supportEmail.trim();
    if (email.isEmpty) {
      issues.add('SUPPORT_EMAIL is missing.');
    } else if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      issues.add('SUPPORT_EMAIL does not look like a valid email address.');
    }

    return issues;
  }
}
