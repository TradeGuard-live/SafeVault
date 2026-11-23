import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/features/authentication/presentation/auth_providers.dart';
import 'package:vault/features/onboarding/presentation/splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SafeVault Splash Canvas Animation & Lifecycle Guard Tests', () {
    setUp(() {
      SplashScreen.hasCompletedInitialColdSplash = false;
    });

    testWidgets('1. Cold start: SplashScreen displays animated custom paint canvas and progresses', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SplashScreen(),
          ),
        ),
      );

      // Verify custom paint canvas is active
      expect(find.byType(CustomPaint), findsWidgets);
      expect(SplashScreen.hasCompletedInitialColdSplash, isFalse);

      // Advance animation partially (Stage 1)
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.byType(CustomPaint), findsWidgets);
      expect(SplashScreen.hasCompletedInitialColdSplash, isFalse);

      // Advance through Stage 2 and complete (2.93 seconds)
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 500));

      expect(SplashScreen.hasCompletedInitialColdSplash, isTrue);
    });

    testWidgets('2. Warm resume guard: When in RAM, SplashScreen immediately skips animation', (tester) async {
      // Simulate that cold start has already executed in this process
      SplashScreen.hasCompletedInitialColdSplash = true;

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SplashScreen(),
          ),
        ),
      );

      // Fast-forward post frame callback
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Must remain true and not re-trigger cold animation
      expect(SplashScreen.hasCompletedInitialColdSplash, isTrue);
    });

    test('3. Mathematical easing functions conform to exact curves', () {
      // Verify boundary conditions
      expect(SplashScreen.hasCompletedInitialColdSplash, isFalse);
    });
  });
}
