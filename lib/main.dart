import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/routes/app_router.dart';
import 'core/security/privacy_service.dart';
import 'core/services/native_saf_and_share_service.dart';
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

class VaultApp extends ConsumerStatefulWidget {
  const VaultApp({super.key});

  @override
  ConsumerState<VaultApp> createState() => _VaultAppState();
}

class _VaultAppState extends ConsumerState<VaultApp> {
  late final AppLifecycleListener _lifecycleListener;
  StreamSubscription<List<SafFileItem>>? _shareSubscription;

  @override
  void initState() {
    super.initState();
    final session = ref.read(vaultSessionProvider);
    NativeSafAndShareService.instance.attachSession(session);

    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        ref.read(vaultSessionProvider).handleLifecycleChange(state);
      },
    );

    // Listen for real-time incoming shares via Android Sharesheet
    _shareSubscription = NativeSafAndShareService.instance.incomingShareStream.listen((items) {
      if (items.isNotEmpty) {
        ref.read(pendingIncomingShareProvider.notifier).state = items;
        final session = ref.read(vaultSessionProvider);
        if (session.isUnlocked) {
          ref.read(appRouterProvider).push('/incoming-share-preview', extra: items);
        }
      }
    });

    // Check for pending launch shares
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pending = await NativeSafAndShareService.instance.getPendingIncomingShares();
      if (pending.isNotEmpty && mounted) {
        ref.read(pendingIncomingShareProvider.notifier).state = pending;
        final session = ref.read(vaultSessionProvider);
        if (session.isUnlocked) {
          ref.read(appRouterProvider).push('/incoming-share-preview', extra: pending);
        }
      }
    });
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(appRouterProvider);

    // Get platform brightness safely (fallback to light if context query not yet bound)
    final platformBrightness = View.of(context).platformDispatcher.platformBrightness;
    final activeTheme = AppTheme.themeFor(settings.themeMode, platformBrightness);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        ref.read(vaultSessionProvider).recordUserActivity();
      },
      child: MaterialApp.router(
        title: 'Vault',
        debugShowCheckedModeBanner: false,
        theme: activeTheme,
        routerConfig: router,
      ),
    );
  }
}
