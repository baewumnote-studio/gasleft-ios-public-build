import 'package:flutter_test/flutter_test.dart';
import 'package:gasleft/domain/models/settings_models.dart';
import 'package:gasleft/services/ad_policy.dart';

AdState buildState({
  int count = 4,
  bool firstSession = true,
  int lastEligible = 0,
  int daily = 0,
  String? dayKey,
  int? lastAt,
}) {
  return AdState(
    completedReadingCount: count,
    interstitialImpressionCount: 0,
    lastInterstitialAtEpochMs: lastAt,
    lastInterstitialDayKey: dayKey,
    dailyInterstitialCount: daily,
    firstSessionCompleted: firstSession,
    lastEligibleReadingCount: lastEligible,
  );
}

void main() {
  final now = DateTime(2026, 10, 7, 14);

  test('first session is blocked', () {
    expect(
      AdPolicy.eligible(
        state: buildState(firstSession: false),
        now: now,
        canRequestAds: true,
        adLoaded: true,
      ),
      isFalse,
    );
  });

  test('first three readings are blocked', () {
    expect(
      AdPolicy.eligible(
        state: buildState(count: 3),
        now: now,
        canRequestAds: true,
        adLoaded: true,
      ),
      isFalse,
    );
  });

  test('fourth reading can be eligible', () {
    expect(
      AdPolicy.eligible(
        state: buildState(),
        now: now,
        canRequestAds: true,
        adLoaded: true,
      ),
      isTrue,
    );
  });

  test('requires four readings since prior eligible impression', () {
    expect(
      AdPolicy.eligible(
        state: buildState(count: 7, lastEligible: 4),
        now: now,
        canRequestAds: true,
        adLoaded: true,
      ),
      isFalse,
    );
  });

  test('daily cap blocks second impression', () {
    final key = AdPolicy.localDayKey(now);
    expect(
      AdPolicy.eligible(
        state: buildState(daily: 1, dayKey: key),
        now: now,
        canRequestAds: true,
        adLoaded: true,
      ),
      isFalse,
    );
  });

  test('missing consent or loaded ad blocks impression', () {
    expect(
      AdPolicy.eligible(
        state: buildState(),
        now: now,
        canRequestAds: false,
        adLoaded: true,
      ),
      isFalse,
    );
    expect(
      AdPolicy.eligible(
        state: buildState(),
        now: now,
        canRequestAds: true,
        adLoaded: false,
      ),
      isFalse,
    );
  });

  test('minimum 15 minute interval is enforced', () {
    final thirteenMinutesAgo = now
        .subtract(const Duration(minutes: 13))
        .millisecondsSinceEpoch;
    expect(
      AdPolicy.eligible(
        state: buildState(lastAt: thirteenMinutesAgo),
        now: now,
        canRequestAds: true,
        adLoaded: true,
      ),
      isFalse,
    );

    final fifteenMinutesAgo = now
        .subtract(const Duration(minutes: 15))
        .millisecondsSinceEpoch;
    expect(
      AdPolicy.eligible(
        state: buildState(lastAt: fifteenMinutesAgo),
        now: now,
        canRequestAds: true,
        adLoaded: true,
      ),
      isTrue,
    );
  });

  test('daily cap resets when stored day is different', () {
    expect(
      AdPolicy.eligible(
        state: buildState(daily: 1, dayKey: '2026-10-06'),
        now: now,
        canRequestAds: true,
        adLoaded: true,
      ),
      isTrue,
    );
  });
  test('future stored timestamp fails closed after device clock rollback', () {
    final future = now.add(const Duration(hours: 1)).millisecondsSinceEpoch;
    expect(
      AdPolicy.eligible(
        state: buildState(lastAt: future),
        now: now,
        canRequestAds: true,
        adLoaded: true,
      ),
      isFalse,
    );
  });

  test('stale daily count without matching local day does not block', () {
    expect(
      AdPolicy.eligible(
        state: buildState(
          count: 8,
          lastEligible: 4,
          daily: 99,
          dayKey: '2026-10-01',
        ),
        now: now,
        canRequestAds: true,
        adLoaded: true,
      ),
      isTrue,
    );
  });
}
