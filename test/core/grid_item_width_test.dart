import 'package:flutter_test/flutter_test.dart';
import 'package:nyumba_property_management/core/presentation/responsive.dart';

void main() {
  test('splits the row evenly once there is room for every column', () {
    expect(gridItemWidth(320, columns: 2, gap: 10), 155);
    expect(gridItemWidth(780, columns: 3, gap: 10), (780 - 20) / 3);
  });

  test('a single column takes the whole row, gap or not', () {
    expect(gridItemWidth(320, columns: 1, gap: 18), 320);
    expect(gridItemWidth(0, columns: 1, gap: 18), 0);
  });

  test(
    'a box too narrow for its columns collapses instead of going negative',
    () {
      // The crash this exists to stop: a zero-width LayoutBuilder asked for two
      // 10-gap columns produced -5, which reaches SizedBox as a non-normalized
      // BoxConstraints and throws rather than laying out badly.
      expect(gridItemWidth(0, columns: 2, gap: 10), 0);
      expect(gridItemWidth(8, columns: 2, gap: 10), 0);
      expect(gridItemWidth(10, columns: 2, gap: 10), 0);
      expect(gridItemWidth(20, columns: 3, gap: 14), 0);
    },
  );

  test('a negative box width never becomes a negative item width', () {
    expect(gridItemWidth(-5, columns: 1, gap: 10), 0);
    expect(gridItemWidth(-5, columns: 3, gap: 10), 0);
  });
}
