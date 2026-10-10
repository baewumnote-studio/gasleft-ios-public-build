import 'package:flutter_test/flutter_test.dart';
import 'package:gasleft/services/reminder_date_calculator.dart';

void main() {
  test('adds calendar days across month end', () {
    final measured = DateTime(2026, 1, 31, 23, 30);
    final due = ReminderDateCalculator.dueCalendarDate(
      measuredAtEpochMs: measured.millisecondsSinceEpoch,
      days: 1,
    );

    expect(due.year, 2026);
    expect(due.month, 2);
    expect(due.day, 1);
    expect(due.hour, 0);
  });

  test('normalizes leap-day calendar arithmetic', () {
    final measured = DateTime(2028, 2, 28, 8);
    final due = ReminderDateCalculator.dueCalendarDate(
      measuredAtEpochMs: measured.millisecondsSinceEpoch,
      days: 1,
    );

    expect(due, DateTime(2028, 2, 29));
  });

  test('supports long reminder periods as civil dates', () {
    final measured = DateTime(2026, 10, 7, 22);
    final due = ReminderDateCalculator.dueCalendarDate(
      measuredAtEpochMs: measured.millisecondsSinceEpoch,
      days: 90,
    );

    expect(due, DateTime(2027, 1, 5));
  });

  test('rejects non-positive days', () {
    expect(
      () => ReminderDateCalculator.dueCalendarDate(
        measuredAtEpochMs: DateTime(2026, 10, 7).millisecondsSinceEpoch,
        days: 0,
      ),
      throwsArgumentError,
    );
  });
  test(
    'past due reminder is not eligible to be re-armed without a new reading',
    () {
      final measured = DateTime(2026, 10, 1, 22, 30);

      expect(
        ReminderDateCalculator.isDueOrPast(
          measuredAtEpochMs: measured.millisecondsSinceEpoch,
          days: 3,
          now: DateTime(2026, 10, 4, 10, 0),
        ),
        isTrue,
      );
      expect(
        ReminderDateCalculator.isDueOrPast(
          measuredAtEpochMs: measured.millisecondsSinceEpoch,
          days: 3,
          now: DateTime(2026, 10, 4, 9, 59),
        ),
        isFalse,
      );
    },
  );
}
