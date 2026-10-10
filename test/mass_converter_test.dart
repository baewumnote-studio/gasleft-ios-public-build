import 'package:flutter_test/flutter_test.dart';
import 'package:gasleft/core/enums.dart';
import 'package:gasleft/domain/services/mass_converter.dart';

void main() {
  group('MassConverter', () {
    test('20 lb rounds to 9072 g', () {
      expect(MassConverter.toGrams(20, MassUnit.lb), 9072);
    });

    test('1 kg is 1000 g', () {
      expect(MassConverter.toGrams(1, MassUnit.kg), 1000);
    });

    test('round trip pounds stays within display tolerance', () {
      final grams = MassConverter.toGrams(17.2, MassUnit.lb);
      final pounds = MassConverter.fromGrams(grams, MassUnit.lb);
      expect((pounds - 17.2).abs(), lessThan(0.01));
    });
  });
}
