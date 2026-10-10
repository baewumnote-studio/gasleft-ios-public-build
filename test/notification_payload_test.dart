import 'package:flutter_test/flutter_test.dart';
import 'package:gasleft/services/notification_payload.dart';

void main() {
  test('extracts cylinder id', () {
    expect(NotificationPayload.cylinderId('cylinder:abc-123'), 'abc-123');
  });

  test('rejects invalid or empty payloads', () {
    expect(NotificationPayload.cylinderId(null), isNull);
    expect(NotificationPayload.cylinderId(''), isNull);
    expect(NotificationPayload.cylinderId('other:abc'), isNull);
    expect(NotificationPayload.cylinderId('cylinder:   '), isNull);
  });
}
