import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/features/dashboard/presentation/widgets/dashboard_charts.dart';

void main() {
  group('monthAxisLabels', () {
    test('labels the months the series actually plots', () {
      // Ten months ending July 2026: index 0 is October 2025.
      final labels = monthAxisLabels(10, DateTime(2026, 7, 17));
      expect(labels.first.label, 'Oct');
      expect(labels.last.label, 'Jul');
      expect(labels.first.position, 0);
      expect(labels.last.position, 1);
      // The regression this guards: the axis used to show days of the
      // current month ("1 Jul", "8 Jul", …) under a monthly series.
      expect(labels.map((entry) => entry.label), isNot(contains('1 Jul')));
    });

    test('positions sit at the fraction of the axis their month occupies', () {
      final labels = monthAxisLabels(10, DateTime(2026, 7, 17));
      for (final entry in labels) {
        expect(entry.position, inInclusiveRange(0, 1));
      }
      expect(
        labels.map((entry) => entry.position).toList(),
        List.of(labels.map((entry) => entry.position))..sort(),
        reason: 'labels must read left to right in time order',
      );
    });

    test('an empty series draws no axis labels', () {
      expect(monthAxisLabels(0, DateTime(2026, 7, 17)), isEmpty);
    });

    test('a single month centres its only label', () {
      final labels = monthAxisLabels(1, DateTime(2026, 7, 17));
      expect(labels.single.label, 'Jul');
      expect(labels.single.position, 0.5);
    });

    test('short series label every point without duplicates', () {
      final labels = monthAxisLabels(3, DateTime(2026, 7, 17));
      expect(labels.map((entry) => entry.label), ['May', 'Jun', 'Jul']);
    });
  });
}
