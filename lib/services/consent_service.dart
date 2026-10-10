import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

class ConsentService {
  bool _infoInitialized = false;
  bool _lastInfoRefreshSucceeded = false;
  bool _lastGatherSucceeded = false;
  Future<void>? _infoRefreshInFlight;
  Future<void>? _gatherInFlight;

  /// Refreshes UMP consent information without presenting a form.
  ///
  /// Google recommends requesting fresh consent information on every app
  /// launch. GasLeft does that even while the app is still deliberately
  /// ad-free; the actual consent form and Mobile Ads SDK remain deferred until
  /// advertising can become relevant.
  Future<void> refreshInfo() {
    if (_infoInitialized && _lastInfoRefreshSucceeded) {
      return Future<void>.value();
    }
    final existing = _infoRefreshInFlight;
    if (existing != null) return existing;

    final completer = Completer<void>();
    _infoRefreshInFlight = completer.future;
    unawaited(() async {
      try {
        _lastInfoRefreshSucceeded = await _performInfoRefresh();
        if (!_lastInfoRefreshSucceeded) _lastGatherSucceeded = false;
      } catch (_) {
        _lastInfoRefreshSucceeded = false;
        _lastGatherSucceeded = false;
      } finally {
        _infoInitialized = true;
        _infoRefreshInFlight = null;
        if (!completer.isCompleted) completer.complete();
      }
    }());
    return completer.future;
  }

  Future<bool> _performInfoRefresh() async {
    final completer = Completer<bool>();
    final params = ConsentRequestParameters();
    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        params,
        () {
          if (!completer.isCompleted) completer.complete(true);
        },
        (formError) {
          if (!completer.isCompleted) completer.complete(false);
        },
      );
    } catch (_) {
      if (!completer.isCompleted) completer.complete(false);
    }
    return completer.future;
  }

  /// Presents a required consent form, if any, but only when the advertising
  /// path actually needs to become active.
  Future<void> gatherConsentIfNeeded() {
    final existing = _gatherInFlight;
    if (existing != null) return existing;

    final completer = Completer<void>();
    _gatherInFlight = completer.future;
    unawaited(() async {
      try {
        if (!_infoInitialized || !_lastInfoRefreshSucceeded) {
          await refreshInfo();
        }
        if (!_lastInfoRefreshSucceeded) {
          _lastGatherSucceeded = false;
          return;
        }
        _lastGatherSucceeded = await _performGather();
      } catch (_) {
        _lastGatherSucceeded = false;
      } finally {
        _gatherInFlight = null;
        if (!completer.isCompleted) completer.complete();
      }
    }());
    return completer.future;
  }

  Future<bool> _performGather() async {
    final completer = Completer<bool>();
    try {
      await ConsentForm.loadAndShowConsentFormIfRequired((formError) {
        if (!completer.isCompleted) completer.complete(formError == null);
      });
    } catch (_) {
      if (!completer.isCompleted) completer.complete(false);
    }
    return completer.future;
  }

  /// Backward-compatible combined operation for tests/tools that need the full
  /// advertising consent flow in one call.
  Future<void> refresh() async {
    await refreshInfo();
    await gatherConsentIfNeeded();
  }

  Future<bool> canRequestAds() async {
    if (!_infoInitialized ||
        !_lastInfoRefreshSucceeded ||
        !_lastGatherSucceeded) {
      return false;
    }
    try {
      return await ConsentInformation.instance.canRequestAds();
    } catch (_) {
      return false;
    }
  }

  Future<bool> privacyOptionsRequired() async {
    if (!_infoInitialized) await refreshInfo();
    if (!_lastInfoRefreshSucceeded) return false;
    try {
      final status = await ConsentInformation.instance
          .getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  Future<void> showPrivacyOptions() async {
    if (!_infoInitialized || !_lastInfoRefreshSucceeded) {
      await refreshInfo();
    }
    if (!_lastInfoRefreshSucceeded) return;

    final completer = Completer<void>();
    var succeeded = false;
    try {
      await ConsentForm.showPrivacyOptionsForm((formError) {
        succeeded = formError == null;
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future;
    } catch (_) {
      if (!completer.isCompleted) completer.complete();
    }
    if (succeeded) _lastGatherSucceeded = true;
  }
}
