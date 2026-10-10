import '../domain/models/settings_models.dart';

abstract final class AdPolicy {
  static bool eligible({
    required AdState state,
    required DateTime now,
    required bool canRequestAds,
    required bool adLoaded,
  }) {
    if (!state.firstSessionCompleted) return false;
    if (!canRequestAds || !adLoaded) return false;
    if (state.completedReadingCount < 4) return false;
    if (state.completedReadingCount - state.lastEligibleReadingCount < 4) {
      return false;
    }

    final dayKey = localDayKey(now);
    final dailyCount = state.lastInterstitialDayKey == dayKey
        ? state.dailyInterstitialCount
        : 0;
    if (dailyCount >= 1) return false;

    final last = state.lastInterstitialAtEpochMs;
    if (last != null) {
      final elapsed = now.difference(DateTime.fromMillisecondsSinceEpoch(last));
      if (elapsed < const Duration(minutes: 15)) return false;
    }
    return true;
  }

  static String localDayKey(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}
