import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:gasleft/core/app_strings.dart';
import 'package:gasleft/core/enums.dart';
import 'package:gasleft/core/formatters.dart';

void main() {
  setUpAll(() => initializeDateFormatting('en'));
  group('massInputValue', () {
    test('preserves gram-level kg precision without trailing zeros', () {
      expect(AppFormatters.massInputValue(10450, MassUnit.kg), '10.45');
      expect(AppFormatters.massInputValue(9000, MassUnit.kg), '9');
    });

    test('keeps enough lb precision for edit round trips', () {
      final text = AppFormatters.massInputValue(7802, MassUnit.lb);
      final parsed = double.parse(text);
      expect(parsed, closeTo(17.2, 0.01));
    });
  });

  test('parseDecimal accepts comma decimal separator', () {
    expect(AppFormatters.parseDecimal('10,45'), 10.45);
  });

  group('DecimalTextInputFormatter', () {
    const formatter = DecimalTextInputFormatter();

    TextEditingValue value(String text) => TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );

    test('allows up to three decimal places', () {
      final result = formatter.formatEditUpdate(
        value('10.12'),
        value('10.123'),
      );
      expect(result.text, '10.123');
    });

    test('allows comma decimal separator', () {
      final result = formatter.formatEditUpdate(value('10'), value('10,5'));
      expect(result.text, '10,5');
    });

    test('rejects a fourth decimal place', () {
      final result = formatter.formatEditUpdate(
        value('10.123'),
        value('10.1234'),
      );
      expect(result.text, '10.123');
    });

    test('rejects a second decimal separator', () {
      final result = formatter.formatEditUpdate(value('10.1'), value('10.1.'));
      expect(result.text, '10.1');
    });

    test('rejects more than four integer digits', () {
      final result = formatter.formatEditUpdate(value('9999'), value('10000'));
      expect(result.text, '9999');
    });
  });
  group('localized date/time copy', () {
    const strings = AppStrings.english;
    final now = DateTime(2026, 10, 7, 12, 0);

    test('uses the localization catalog for relative time', () {
      expect(
        AppFormatters.timeAgo(
          now.subtract(const Duration(seconds: 20)).millisecondsSinceEpoch,
          strings,
          now: now,
        ),
        'Just now',
      );
      expect(
        AppFormatters.timeAgo(
          now.subtract(const Duration(minutes: 7)).millisecondsSinceEpoch,
          strings,
          now: now,
        ),
        '7m ago',
      );
      expect(
        AppFormatters.timeAgo(
          now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch,
          strings,
          now: now,
        ),
        '3h ago',
      );
      expect(
        AppFormatters.timeAgo(
          now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
          strings,
          now: now,
        ),
        'Yesterday',
      );
      expect(
        AppFormatters.timeAgo(
          now.subtract(const Duration(days: 6)).millisecondsSinceEpoch,
          strings,
          now: now,
        ),
        '6 days ago',
      );
    });

    test('formats long dates using the catalog locale', () {
      final value = DateTime(2026, 10, 7, 9, 30).millisecondsSinceEpoch;
      final formatted = AppFormatters.dateTime(value, strings);
      expect(formatted, contains('Oct'));
      expect(formatted, contains('2026'));
    });
  });
}
