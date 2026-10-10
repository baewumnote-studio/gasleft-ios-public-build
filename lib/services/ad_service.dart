import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/app_config.dart';
import '../data/gas_repository.dart';
import 'ad_policy.dart';
import 'consent_service.dart';

class AdService {
  AdService(this._repository, this._consent);

  final GasRepository _repository;
  final ConsentService _consent;
  InterstitialAd? _interstitial;
  bool _loading = false;
  bool _mobileAdsInitialized = false;
  bool _impressionShownThisSession = false;
  int _loadGeneration = 0;

  Future<void> bootstrap() async {
    // UMP consent information itself is refreshed on every app launch by
    // BootstrapScreen. A potentially interruptive consent form and the Mobile
    // Ads SDK remain deferred until an interstitial can actually become
    // relevant (returning session + four completed readings).
    // Advertising is optional. SDK/network/configuration failures must never
    // become unhandled startup errors or interfere with the offline utility.
    try {
      final state = await _repository.getAdState();
      if (!state.firstSessionCompleted || state.completedReadingCount < 4) {
        return;
      }
      await _consent.gatherConsentIfNeeded();
      if (!await _consent.canRequestAds()) return;
      if (!await _ensureMobileAdsInitialized()) return;
      await preload();
    } catch (_) {}
  }

  Future<bool> _ensureMobileAdsInitialized() async {
    if (_mobileAdsInitialized) return true;
    try {
      await MobileAds.instance.initialize();
      _mobileAdsInitialized = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> preload() async {
    if (_loading || _interstitial != null) return;
    if (!AppConfig.hasAdUnitForCurrentBuild) return;
    if (!await _consent.canRequestAds()) return;
    _loading = true;
    final generation = _loadGeneration;
    final completer = Completer<void>();

    try {
      await InterstitialAd.load(
        adUnitId: AppConfig.interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            if (generation != _loadGeneration) {
              // Consent/privacy choices changed while this request was in
              // flight. Never retain an ad requested under the old state.
              unawaited(_disposeAdSafely(ad));
              if (!completer.isCompleted) completer.complete();
              return;
            }
            _interstitial = ad;
            _loading = false;
            if (!completer.isCompleted) completer.complete();
          },
          onAdFailedToLoad: (error) {
            if (generation == _loadGeneration) _loading = false;
            if (!completer.isCompleted) completer.complete();
          },
        ),
      );
      await completer.future;
    } catch (_) {
      if (generation == _loadGeneration) _loading = false;
      if (!completer.isCompleted) completer.complete();
    }
  }

  /// Opens UMP privacy choices and invalidates any ad loaded under the
  /// previous consent state before another request can be made.
  Future<void> presentPrivacyOptions() async {
    _loadGeneration += 1;
    _loading = false;
    final staleAd = _interstitial;
    _interstitial = null;
    if (staleAd != null) unawaited(_disposeAdSafely(staleAd));

    await _consent.showPrivacyOptions();

    if (!await _consent.canRequestAds()) return;
    if (!await _ensureMobileAdsInitialized()) return;
    await preload();
  }

  Future<bool> showIfEligibleAfterResult() async {
    // Extra in-memory safety: even if local accounting fails after a real
    // impression, never show another interstitial during the same app session.
    if (_impressionShownThisSession) return false;

    final canRequest = await _consent.canRequestAds();
    final state = await _repository.getAdState();
    final now = DateTime.now();

    if (!AdPolicy.eligible(
      state: state,
      now: now,
      canRequestAds: canRequest,
      adLoaded: _interstitial != null,
    )) {
      if (_interstitial == null && canRequest) unawaited(preload());
      return false;
    }

    final ad = _interstitial;
    if (ad == null) return false;
    _interstitial = null;
    final completer = Completer<bool>();

    Future<void>? exposureWrite;
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdShowedFullScreenContent: (_) {
        _impressionShownThisSession = true;
        // The product cap is about what the user actually sees, not whether an
        // analytics impression callback arrives before the process is killed.
        // Persist the local cap as soon as full-screen content is shown.
        exposureWrite ??= _recordExposureSafely(now);
      },
      onAdImpression: (_) {
        _impressionShownThisSession = true;
      },
      onAdDismissedFullScreenContent: (shownAd) {
        unawaited(_disposeAdSafely(shownAd));
        unawaited(
          _finishDismissal(completer: completer, exposureWrite: exposureWrite),
        );
      },
      onAdFailedToShowFullScreenContent: (failedAd, error) {
        unawaited(_disposeAdSafely(failedAd));
        if (!completer.isCompleted) completer.complete(false);
        unawaited(preload());
      },
    );

    try {
      await ad.show();
    } catch (_) {
      await _disposeAdSafely(ad);
      if (!completer.isCompleted) completer.complete(false);
      unawaited(preload());
    }
    return completer.future;
  }

  Future<void> _disposeAdSafely(InterstitialAd? ad) async {
    if (ad == null) return;
    try {
      await ad.dispose();
    } catch (_) {
      // Ad cleanup is never allowed to affect the offline core flow.
    }
  }

  Future<void> _finishDismissal({
    required Completer<bool> completer,
    required Future<void>? exposureWrite,
  }) async {
    if (exposureWrite != null) await exposureWrite;
    if (!completer.isCompleted) completer.complete(true);
    unawaited(preload());
  }

  Future<void> _recordExposureSafely(DateTime now) async {
    try {
      await _repository.recordInterstitialImpression(
        atEpochMs: now.millisecondsSinceEpoch,
        dayKey: AdPolicy.localDayKey(now),
      );
    } catch (_) {
      // Local ad accounting is secondary to the offline utility. The in-memory
      // same-session guard still prevents a second interstitial in this run.
    }
  }

  void dispose() {
    _loadGeneration += 1;
    _loading = false;
    final ad = _interstitial;
    _interstitial = null;
    if (ad != null) unawaited(_disposeAdSafely(ad));
  }
}
