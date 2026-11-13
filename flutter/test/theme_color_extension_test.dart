import 'package:flutter_hbb/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('theme color interpolation preserves both endpoints', () {
    final light = ColorThemeExtension.light;
    final dark = ColorThemeExtension.dark;

    for (final endpoints in [(light, dark), (dark, light)]) {
      for (final t in [0.0, 1.0]) {
        final actual =
            endpoints.$1.lerp(endpoints.$2, t) as ColorThemeExtension;
        final expected = t == 0 ? endpoints.$1 : endpoints.$2;
        expect(
          [
            actual.errorBannerBg,
            actual.me,
            actual.toastBg,
            actual.toastText,
            actual.divider
          ].map((color) => color?.value).toList(),
          [
            expected.errorBannerBg,
            expected.me,
            expected.toastBg,
            expected.toastText,
            expected.divider
          ].map((color) => color?.value).toList(),
        );
      }
    }
  });
}
