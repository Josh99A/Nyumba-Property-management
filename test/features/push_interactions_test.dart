import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/features/notifications/application/push_interactions.dart';

void main() {
  test('push deep links accept only known application routes', () {
    expect(safeNotificationRoute('/tenant/maintenance'), '/tenant/maintenance');
    expect(safeNotificationRoute('/listings'), '/listings');
    expect(safeNotificationRoute('https://example.com'), isNull);
    expect(safeNotificationRoute('//example.com'), isNull);
    expect(safeNotificationRoute('/unknown'), isNull);
    expect(safeNotificationRoute(null), isNull);
  });
}
