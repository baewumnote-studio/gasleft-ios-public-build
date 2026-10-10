abstract final class NotificationPayload {
  static const _cylinderPrefix = 'cylinder:';

  static String? cylinderId(String? payload) {
    if (payload == null || !payload.startsWith(_cylinderPrefix)) return null;
    final value = payload.substring(_cylinderPrefix.length).trim();
    return value.isEmpty ? null : value;
  }
}
