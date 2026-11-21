import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/local_notification_service.dart';
import 'core/routes/app_router.dart';
import 'core/security/privacy_service.dart';
import 'core/services/native_saf_and_share_service.dart';
import 'core/theme/app_theme.dart';
import 'features/authentication/presentation/auth_providers.dart';

class StartupDiagnostics {
  final String serviceName;
  final String error;
  final DateTime timestamp;

  StartupDiagnostics({required this.serviceName, required this.error})
    : timestamp = DateTime.now();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Do not await noncritical platform work before the first Flutter frame.
  // MainActivity enables FLAG_SECURE natively in onCreate, so moving this
  // configuration after runApp does not expose the vault to screenshots.
  runApp(const ProviderScope(child: VaultApp()));
}

class VaultApp extends ConsumerStatefulWidget {
  const VaultApp({super.key});

  @override
  ConsumerState<VaultApp> createState() => _VaultAppState();
}

class _VaultAppState extends ConsumerState<VaultApp> {
  late final AppLifecycleListener _lifecycleListener;
  StreamSubscription<List<SafFileItem>>? _shareSubscription;
  StartupDiagnostics? _startupDiagnostics;

  @override
  void initState() {
    super.initState();
    final session = ref.read(vaultSessionProvider);
    NativeSafAndShareService.instance.attachSession(session);
    ref.read(biometricServiceProvider).attachVaultSession(session);
    unawaited(_initializeNonCriticalServices());

    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        ref.read(vaultSessionProvider).handleLifecycleChange(state);
      },
    );

    // Listen for real-time incoming shares via Android Sharesheet
    _shareSubscription = NativeSafAndShareService.instance.incomingShareStream
        .listen((items) {
          if (items.isNotEmpty) {
            ref.read(pendingIncomingShareProvider.notifier).state = items;
            final session = ref.read(vaultSessionProvider);
            if (session.isUnlocked) {
              ref
                  .read(appRouterProvider)
                  .push('/incoming-share-preview', extra: items);
            }
          }
        });

    // Check for pending launch shares
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pending = await NativeSafAndShareService.instance
          .getPendingIncomingShares();
      if (pending.isNotEmpty && mounted) {
        ref.read(pendingIncomingShareProvider.notifier).state = pending;
        final session = ref.read(vaultSessionProvider);
        if (session.isUnlocked) {
          ref
              .read(appRouterProvider)
              .push('/incoming-share-preview', extra: pending);
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

  Future<void> _initializeNonCriticalServices() async {
    await _runStartupTask(
      serviceName: 'Display configuration',
      task: () => SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]),
    );
    await _runStartupTask(
      serviceName: 'Screenshot protection',
      // FLAG_SECURE is already active in MainActivity before Flutter renders.
      task: () => PrivacyService.setScreenshotProtection(true),
    );
    await _runStartupTask(
      serviceName: 'Local notifications',
      task: () => LocalNotificationService.instance.initialize(),
    );
  }

  Future<void> _runStartupTask({
    required String serviceName,
    required Future<dynamic> Function() task,
  }) async {
    try {
      await task();
    } catch (error) {
      debugPrint('Startup notice: $serviceName: $error');
      if (mounted && _startupDiagnostics == null) {
        setState(() {
          _startupDiagnostics = StartupDiagnostics(
            serviceName: serviceName,
            error: error.toString(),
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(appRouterProvider);

    // Get platform brightness safely (fallback to light if context query not yet bound)
    final platformBrightness = View.of(context)
        .platformDispatcher
        .platformBrightness;
    final activeTheme = AppTheme.themeFor(
      settings.themeMode,
      platformBrightness,
    );

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
        builder: (context, child) {
          final diagnostics = _startupDiagnostics;
          if (!kDebugMode || diagnostics == null) {
            return child ?? const SizedBox.shrink();
          }

          return Stack(
            children: [
              child ?? const SizedBox.shrink(),
              SafeArea(
                child: Material(
                  color: Colors.amber.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '${diagnostics.serviceName} failed during startup: ${diagnostics.error}',
                      style: const TextStyle(color: Colors.black, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
