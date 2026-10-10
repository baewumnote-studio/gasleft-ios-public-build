import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gasleft/core/enums.dart';
import 'package:gasleft/data/app_database.dart';
import 'package:gasleft/data/gas_repository.dart';
import 'package:gasleft/services/ad_service.dart';
import 'package:gasleft/services/consent_service.dart';

class _CountingConsentService extends ConsentService {
  int gatherCalls = 0;

  @override
  Future<void> gatherConsentIfNeeded() async {
    gatherCalls += 1;
  }

  @override
  Future<bool> canRequestAds() async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase database;
  late GasRepository repository;
  late _CountingConsentService consent;
  late AdService ads;

  setUp(() {
    database = AppDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePathOverride: inMemoryDatabasePath,
    );
    repository = GasRepository(database);
    consent = _CountingConsentService();
    ads = AdService(repository, consent);
  });

  tearDown(() async {
    ads.dispose();
    await database.close();
  });

  Future<String> seedCylinder() => repository.createCylinder(
    name: 'BBQ',
    useCase: CylinderUseCase.bbq,
    preferredUnit: MassUnit.kg,
    tareGrams: 10000,
    capacityGrams: 9000,
    lowThresholdPct: 20,
  );

  Future<void> addReading(String cylinderId, int index) async {
    final cylinder = (await repository.getCylinder(cylinderId))!;
    await repository.addReading(
      cylinder: cylinder,
      measuredAtEpochMs: DateTime(2026, 10, 1 + index).millisecondsSinceEpoch,
      totalWeightGrams: 15000 - index * 100,
      eventType: ReadingEventType.normal,
      validationFlag: ReadingValidationFlag.normal,
      excludedFromPrediction: false,
    );
  }

  test(
    'consent form gathering is deferred before four completed readings',
    () async {
      await repository.markFirstSessionCompleted();
      final id = await seedCylinder();
      for (var i = 0; i < 3; i += 1) {
        await addReading(id, i);
      }

      await ads.bootstrap();

      expect(consent.gatherCalls, 0);
    },
  );

  test('consent form gathering starts at the four-reading threshold', () async {
    await repository.markFirstSessionCompleted();
    final id = await seedCylinder();
    for (var i = 0; i < 4; i += 1) {
      await addReading(id, i);
    }

    await ads.bootstrap();

    expect(consent.gatherCalls, 1);
  });
}
