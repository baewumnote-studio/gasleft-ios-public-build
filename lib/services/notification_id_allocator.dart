class NotificationIdAllocator {
  const NotificationIdAllocator._();

  static int baseId(String stableId) {
    final hex = stableId.replaceAll('-', '');
    final source = hex.length >= 8 ? hex.substring(0, 8) : hex.padRight(8, '0');
    final parsed = int.tryParse(source, radix: 16);
    if (parsed == null) {
      // Fallback for an unexpected non-UUID identifier. Keep the value in the
      // positive signed 31-bit range accepted by notification APIs.
      return stableId.hashCode & 0x7fffffff;
    }
    return parsed & 0x7fffffff;
  }

  static int nextAvailable(String stableId, Set<int> occupied) {
    var candidate = baseId(stableId);
    // Avoid using a negative value; zero is valid but starting at one makes
    // diagnostics easier and leaves zero available for future app-wide uses.
    if (candidate == 0) candidate = 1;
    final start = candidate;
    while (occupied.contains(candidate)) {
      candidate = candidate == 0x7fffffff ? 1 : candidate + 1;
      if (candidate == start) {
        throw StateError('No local notification identifiers are available.');
      }
    }
    return candidate;
  }
}
