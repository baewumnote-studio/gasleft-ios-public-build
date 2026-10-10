import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'app_strings.dart';
import 'enums.dart';
import '../domain/services/mass_converter.dart';

abstract final class AppFormatters {
  static String mass(int grams, MassUnit unit, {int decimals = 1}) {
    final value = MassConverter.fromGrams(grams, unit);
    return '${value.toStringAsFixed(decimals)} ${unit.label}';
  }

  static String percent(double value) => '${value.round()}%';

  static String massInputValue(int grams, MassUnit unit) {
    final value = MassConverter.fromGrams(grams, unit);
    var text = value.toStringAsFixed(3);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
    return text;
  }

  static String dateTime(int epochMs, AppStrings strings) {
    final locale = strings.locale.toLanguageTag();
    return DateFormat.yMMMd(
      locale,
    ).add_jm().format(DateTime.fromMillisecondsSinceEpoch(epochMs));
  }

  static String timeAgo(int epochMs, AppStrings strings, {DateTime? now}) {
    final then = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final diff = (now ?? DateTime.now()).difference(then);
    if (diff.inMinutes < 1) return strings.text('timeJustNow');
    if (diff.inHours < 1) {
      return strings.text('timeMinutesAgo', {'minutes': diff.inMinutes});
    }
    if (diff.inDays < 1) {
      return strings.text('timeHoursAgo', {'hours': diff.inHours});
    }
    if (diff.inDays == 1) return strings.text('timeYesterday');
    if (diff.inDays < 30) {
      return strings.text('timeDaysAgo', {'days': diff.inDays});
    }
    return DateFormat.MMMd(strings.locale.toLanguageTag()).format(then);
  }

  static double? parseDecimal(String input) {
    return double.tryParse(input.trim().replaceAll(',', '.'));
  }
}

class DecimalTextInputFormatter extends TextInputFormatter {
  const DecimalTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    if (!RegExp(r'^\d{0,4}([.,]\d{0,3})?$').hasMatch(text)) {
      return oldValue;
    }
    return newValue;
  }
}
