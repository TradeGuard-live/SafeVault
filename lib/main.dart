import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/routes/app_router.dart';
import 'core/security/privacy_service.dart';
import 'core/theme/app_theme.dart';
import 'features/authentication/presentation/auth_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI orientation & overlays
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Privacy First: Block screenshots & hide recent-apps previews by default
  await PrivacyService.setScreenshotProtection(true);

  // Initialize local notifications service offline
  await LocalNotificationService.instance.initialize();

  runApp(
    const ProviderScope(
      child: VaultApp(),
    ),
  );
}

class VaultApp extends ConsumerWidget {
  const VaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(appRouterProvider);

    ThemeMode themeMode;
    switch (settings.themeMode) {
      case 'dark':
        themeMode = ThemeMode.dark;
        break;
      case 'light':
        themeMode = ThemeMode.light;
        break;
      default:
        themeMode = ThemeMode.system;
    }

    return MaterialApp.router(
      title: 'Vault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
