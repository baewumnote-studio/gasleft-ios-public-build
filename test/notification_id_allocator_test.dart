import 'package:flutter_test/flutter_test.dart';
import 'package:gasleft/services/notification_id_allocator.dart';

void main() {
  test('stable UUID prefix produces deterministic positive identifier', () {
    final a = NotificationIdAllocator.baseId(
      '12345678-0000-0000-0000-000000000001',
    );
    final b = NotificationIdAllocator.baseId(
      '12345678-ffff-ffff-ffff-ffffffffffff',
    );

    expect(a, b);
    expect(a, greaterThan(0));
    expect(a, lessThanOrEqualTo(0x7fffffff));
  });

  test('collision advances to the next available identifier', () {
    final base = NotificationIdAllocator.baseId(
      '12345678-0000-0000-0000-000000000001',
    );
    final allocated = NotificationIdAllocator.nextAvailable(
      '12345678-ffff-ffff-ffff-ffffffffffff',
      {base, base + 1},
    );

    expect(allocated, base + 2);
  });

  test('wraps at signed 31-bit maximum', () {
    final allocated = NotificationIdAllocator.nextAvailable(
      'ffffffff-0000-0000-0000-000000000001',
      {0x7fffffff},
    );
    expect(allocated, 1);
  });
}
