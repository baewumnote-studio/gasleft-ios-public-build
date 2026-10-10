import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gasleft/app/providers.dart';
import 'package:gasleft/services/consent_service.dart';

class _FakeConsentService extends ConsentService {
  int refreshInfoCalls = 0;
  int privacyRequirementCalls = 0;

  @override
  Future<void> refreshInfo() async {
    refreshInfoCalls += 1;
  }

  @override
  Future<bool> privacyOptionsRequired() async {
    privacyRequirementCalls += 1;
    return true;
  }
}

void main() {
  test(
    'privacy-options requirement is not gated by reading count or ad eligibility',
    () async {
      final consent = _FakeConsentService();
      final container = ProviderContainer(
        overrides: [consentServiceProvider.overrideWithValue(consent)],
      );
      addTearDown(container.dispose);

      final required = await container.read(
        privacyOptionsRequiredProvider.future,
      );

      expect(required, isTrue);
      expect(consent.refreshInfoCalls, 1);
      expect(consent.privacyRequirementCalls, 1);
    },
  );
}
