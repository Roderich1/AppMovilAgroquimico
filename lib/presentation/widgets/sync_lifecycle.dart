import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/sync/sync_providers.dart';

/// Arranca el worker de Sync v1 al iniciar la app y mientras esté en primer
/// plano; lo detiene en segundo plano. Sólo lo instala `main.dart`, así las
/// pruebas de pantalla no heredan temporizadores.
class SyncLifecycle extends ConsumerStatefulWidget {
  const SyncLifecycle({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SyncLifecycle> createState() => _SyncLifecycleState();
}

class _SyncLifecycleState extends ConsumerState<SyncLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(syncControllerProvider.notifier).startForeground();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(syncControllerProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      controller.startForeground();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      controller.stopForeground();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
