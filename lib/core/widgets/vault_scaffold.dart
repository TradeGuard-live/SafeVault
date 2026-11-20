import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/authentication/presentation/auth_providers.dart';

class VaultScaffold extends ConsumerStatefulWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;
  final bool monitorActivity;

  const VaultScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.backgroundColor,
    this.monitorActivity = true,
  });

  @override
  ConsumerState<VaultScaffold> createState() => _VaultScaffoldState();
}

class _VaultScaffoldState extends ConsumerState<VaultScaffold> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.monitorActivity) {
      final session = ref.read(vaultSessionProvider);
      session.handleLifecycleChange(state);
    }
  }

  void _onUserPointerEvent(PointerDownEvent event) {
    if (widget.monitorActivity) {
      ref.read(vaultSessionProvider).recordUserActivity();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onUserPointerEvent,
      child: Scaffold(
        backgroundColor: widget.backgroundColor,
        appBar: widget.appBar,
        body: widget.body,
        floatingActionButton: widget.floatingActionButton,
        bottomNavigationBar: widget.bottomNavigationBar,
      ),
    );
  }
}

