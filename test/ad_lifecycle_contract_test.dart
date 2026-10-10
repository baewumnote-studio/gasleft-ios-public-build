import 'package:flutter_test/flutter_test.dart';
import 'package:gasleft/core/enums.dart';
import 'package:gasleft/data/app_database.dart';
import 'package:gasleft/data/gas_repository.dart';
import 'package:gasleft/domain/models/cylinder.dart';
import 'package:gasleft/services/ad_policy.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late AppDatabase database;
  late GasRepository repository;

  setUp(() {
    database = AppDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePathOverride: inMemoryDatabasePath,
    );
    repository = GasRepository(database);
  });

  tearDown(() async => database.close());

  Future<Cylinder> seedCylinder() async {
    final id = await repository.createCylinder(
      name: 'BBQ',
      useCase: CylinderUseCase.bbq,
      preferredUnit: MassUnit.kg,
      tareGrams: 10000,
      capacityGrams: 9000,
      lowThresholdPct: 20,
    );
    return (await repository.getCylinder(id))!;
  }

  Future<void> addValidReading(Cylinder cylinder, {required int index}) async {
    await repository.addReading(
      cylinder: cylinder,
      measuredAtEpochMs: DateTime(
        2026,
        10,
        1 + index,
        12,
      ).millisecondsSinceEpoch,
      totalWeightGrams: 18000 - (index * 500),
      eventType: ReadingEventType.normal,
      validationFlag: ReadingValidationFlag.normal,
      excludedFromPrediction: false,
    );
  }

  test(
    'first session stays ad-free even after four completed readings',
    () async {
      final cylinder = await seedCylinder();
      for (var i = 0; i < 4; i++) {
        await addValidReading(cylinder, index: i);
      }

      final state = await repository.getAdState();
      expect(state.completedReadingCount, 4);
      expect(state.firstSessionCompleted, isFalse);
      expect(
        AdPolicy.eligible(
          state: state,
          now: DateTime(2026, 10, 7, 14),
          canRequestAds: true,
          adLoaded: true,
        ),
        isFalse,
      );
    },
  );

  test(
    'second launch unlocks eligibility, impression records caps, next day needs four new actions',
    () async {
      final cylinder = await seedCylinder();
      for (var i = 0; i < 4; i++) {
        await addValidReading(cylinder, index: i);
      }

      await repository.markFirstSessionCompleted();
      var state = await repository.getAdState();
      final firstOpportunity = DateTime(2026, 10, 7, 14);
      expect(
        AdPolicy.eligible(
          state: state,
          now: firstOpportunity,
          canRequestAds: true,
          adLoaded: true,
        ),
        isTrue,
      );

      await repository.recordInterstitialImpression(
        atEpochMs: firstOpportunity.millisecondsSinceEpoch,
        dayKey: AdPolicy.localDayKey(firstOpportunity),
      );
      state = await repository.getAdState();
      expect(state.lastEligibleReadingCount, 4);
      expect(state.dailyInterstitialCount, 1);
      expect(state.interstitialImpressionCount, 1);

      // Same day is blocked even after four more completed reading actions.
      for (var i = 4; i < 8; i++) {
        await addValidReading(cylinder, index: i);
      }
      state = await repository.getAdState();
      expect(state.completedReadingCount, 8);
      expect(
        AdPolicy.eligible(
          state: state,
          now: firstOpportunity.add(const Duration(hours: 2)),
          canRequestAds: true,
          adLoaded: true,
        ),
        isFalse,
      );

      // On a new local day the daily cap resets. Four actions since the prior
      // impression and the 15-minute guard have both been satisfied.
      expect(
        AdPolicy.eligible(
          state: state,
          now: DateTime(2026, 10, 8, 10),
          canRequestAds: true,
          adLoaded: true,
        ),
        isTrue,
      );
    },
  );
}
