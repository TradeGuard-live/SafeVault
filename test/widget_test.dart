import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/main.dart';

void main() {
  testWidgets('App smoke test initializes VaultApp', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: VaultApp()));
    // Drain splash screen timer
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.byType(VaultApp), findsOneWidget);
  });
}
