import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/core/theme/app_theme.dart';
import 'package:vault/core/theme/app_theme_colors.dart';
import 'package:vault/core/widgets/rupee_bunny_mascot.dart';

void main() {
  group('RupeeFlow 4-Theme System Tests', () {
    test('AppThemeColors.fromId maps all 4 themes correctly', () {
      final dark1 = AppThemeColors.fromId('dark');
      final dark2 = AppThemeColors.fromId('rupeeflow_dark');
      expect(dark1.id, equals('dark'));
      expect(dark2.id, equals('dark'));
      expect(dark1.primaryAccent, equals(const Color(0xFF3B82F6)));

      final peachy = AppThemeColors.fromId('peachy');
      expect(peachy.id, equals('peachy'));
      expect(peachy.background, equals(const Color(0xFFFFF8F1)));
      expect(peachy.primaryAccent, equals(const Color(0xFFF58B72)));
      expect(peachy.textPrimary, equals(const Color(0xFF4A3028)));

      final lavender = AppThemeColors.fromId('lavender');
      expect(lavender.id, equals('lavender'));
      expect(lavender.background, equals(const Color(0xFFF7F3FC)));
      expect(lavender.primaryAccent, equals(const Color(0xFF9274C8)));
      expect(lavender.textPrimary, equals(const Color(0xFF342A45)));

      final midnight = AppThemeColors.fromId('midnight_mochi');
      expect(midnight.id, equals('midnight_mochi'));
      expect(midnight.background, equals(const Color(0xFF100E19)));
      expect(midnight.primaryAccent, equals(const Color(0xFFB49AEF)));
      expect(midnight.accentSecondary, equals(const Color(0xFFF0A9D5)));
    });

    test('ThemeData generation sets correct Brightness and extensions', () {
      final peachyTheme = AppTheme.themeFor('peachy', Brightness.light);
      expect(peachyTheme.brightness, equals(Brightness.light));
      expect(peachyTheme.extension<AppThemeColors>(), isNotNull);
      expect(peachyTheme.scaffoldBackgroundColor, equals(const Color(0xFFFFF8F1)));

      final lavenderTheme = AppTheme.themeFor('lavender', Brightness.light);
      expect(lavenderTheme.brightness, equals(Brightness.light));
      expect(lavenderTheme.scaffoldBackgroundColor, equals(const Color(0xFFF7F3FC)));

      final midnightTheme = AppTheme.themeFor('midnight_mochi', Brightness.dark);
      expect(midnightTheme.brightness, equals(Brightness.dark));
      expect(midnightTheme.scaffoldBackgroundColor, equals(const Color(0xFF100E19)));

      final darkTheme = AppTheme.themeFor('rupeeflow_dark', Brightness.dark);
      expect(darkTheme.brightness, equals(Brightness.dark));
      expect(darkTheme.scaffoldBackgroundColor, equals(const Color(0xFF0A0E17)));
    });

    test('All theme presets have non-null gradients, shadows, and status colors', () {
      final allThemes = [
        AppThemeColors.rupeeFlowDark,
        AppThemeColors.peachy,
        AppThemeColors.lavender,
        AppThemeColors.midnightMochi,
      ];

      for (final t in allThemes) {
        expect(t.heroGradient.colors.length, greaterThanOrEqualTo(2));
        expect(t.cardGradient.colors.length, greaterThanOrEqualTo(2));
        expect(t.cardShadow.length, greaterThanOrEqualTo(1));
        expect(t.floatingShadow.length, greaterThanOrEqualTo(1));
        expect(t.success, isNotNull);
        expect(t.error, isNotNull);
        expect(t.warning, isNotNull);
        expect(t.info, isNotNull);
      }
    });

    testWidgets('RupeeBunnyMascot renders in all 7 poses', (tester) async {
      for (final pose in MascotPose.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: RupeeBunnyMascot(
                  pose: pose,
                  size: 100,
                  animated: false,
                ),
              ),
            ),
          ),
        );

        expect(find.byType(RupeeBunnyMascot), findsOneWidget);
        await tester.pumpAndSettle();
      }
    });
  });
}

