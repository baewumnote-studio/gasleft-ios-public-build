import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gasleft/data/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('concurrent first access shares one opened database handle', () async {
    final database = AppDatabase(
      databaseFactoryOverride: databaseFactoryFfi,
      databasePathOverride: inMemoryDatabasePath,
    );

    try {
      final handles = await Future.wait([
        database.db,
        database.db,
        database.db,
      ]);

      expect(identical(handles[0], handles[1]), isTrue);
      expect(identical(handles[1], handles[2]), isTrue);
      final settings = await handles[0].query('app_settings');
      expect(settings, hasLength(1));
    } finally {
      await database.close();
    }
  });
}
