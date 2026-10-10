import 'package:flutter_test/flutter_test.dart';

import 'package:gasleft/core/url_utils.dart';

void main() {
  test('non-HTTP query encoding percent-encodes spaces and symbols', () {
    final encoded = encodeNonHttpQueryParameters({
      'subject': 'GasLeft ad report',
      'body': 'Bad ad: 50% & unsafe?',
    });

    expect(encoded, contains('subject=GasLeft%20ad%20report'));
    expect(encoded, contains('body=Bad%20ad%3A%2050%25%20%26%20unsafe%3F'));
    expect(encoded, isNot(contains('+')));
  });
}
