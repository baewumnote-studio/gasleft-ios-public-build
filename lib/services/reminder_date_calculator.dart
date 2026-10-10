class ReminderDateCalculator {
  const ReminderDateCalculator._();

  /// Returns the local calendar date that is [days] days after the reading.
  ///
  /// We construct the target by calendar components instead of adding a
  /// 24-hour duration. That avoids daylight-saving transitions changing which
  /// civil date the user meant by "N days later".
  static DateTime dueCalendarDate({
    required int measuredAtEpochMs,
    required int days,
  }) {
    if (days < 1) {
      throw ArgumentError.value(days, 'days', 'must be at least 1');
    }
    final measured = DateTime.fromMillisecondsSinceEpoch(
      measuredAtEpochMs,
    ).toLocal();
    return DateTime(measured.year, measured.month, measured.day + days);
  }

  static DateTime dueLocalDateTime({
    required int measuredAtEpochMs,
    required int days,
    int hour = 10,
  }) {
    final date = dueCalendarDate(
      measuredAtEpochMs: measuredAtEpochMs,
      days: days,
    );
    return DateTime(date.year, date.month, date.day, hour);
  }

  static bool isDueOrPast({
    required int measuredAtEpochMs,
    required int days,
    DateTime? now,
    int hour = 10,
  }) {
    final due = dueLocalDateTime(
      measuredAtEpochMs: measuredAtEpochMs,
      days: days,
      hour: hour,
    );
    return !due.isAfter((now ?? DateTime.now()).toLocal());
  }
}
