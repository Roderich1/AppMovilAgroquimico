import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../installation_access.dart';
import '../../services/auth/access_recovery.dart';
import '../../services/auth/existing_session_providers.dart';
import '../../services/auth/remote_session_providers.dart';
import '../../services/sync/sync_access.dart';
import '../../services/sync/union_refresh.dart';
import '../theme/agro_theme.dart';

/// Como SyncLifecycle, se activa desde el punto de entrada de la app.
final unionAutoRefreshEnabledProvider = Provider<bool>((ref) => false);

final unionConnectivityProvider = StreamProvider.autoDispose<bool>((
  ref,
) async* {
  final connectivity = Connectivity();
  bool connected(List<ConnectivityResult> values) =>
      values.any((value) => value != ConnectivityResult.none);
  yield connected(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(connected).distinct();
});

Future<void> refreshUnionNow(
  BuildContext context,
  WidgetRef ref,
  Set<UnionFeed> feeds,
) async {
  bool openAccessScreen() {
    final router = GoRouter.maybeOf(context);
    if (router == null ||
        ref.read(syncAccessHolderProvider).forUnionReads != null) {
      return false;
    }
    final recovery = accessRecoveryModeFor(
      ref.read(installationAccessProvider),
      ref.read(effectiveLocalSessionProvider),
    );
    if (recovery == AccessRecoveryMode.signInAsOwner) {
      router.push('/recuperar');
    } else if (ref.read(remoteSessionProvider).needsReauthentication) {
      router.push('/reauth');
    } else {
      return false;
    }
    return true;
  }

  final connected =
      !ref.read(unionAutoRefreshEnabledProvider) ||
      (ref.read(unionConnectivityProvider).value ?? true);
  if (connected && openAccessScreen()) return;
  await ref
      .read(unionRefreshProvider.notifier)
      .refresh(feeds, manual: true, connected: connected);
  if (context.mounted &&
      connected &&
      (ModalRoute.isCurrentOf(context) ?? true)) {
    openAccessScreen();
  }
}

class UnionUpdates extends ConsumerStatefulWidget {
  const UnionUpdates({super.key, required this.feeds, required this.child});

  final Set<UnionFeed> feeds;
  final Widget child;

  @override
  ConsumerState<UnionUpdates> createState() => _UnionUpdatesState();
}

class _UnionUpdatesState extends ConsumerState<UnionUpdates>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _visible = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.isCurrentOf(context) ?? true;
    if (_visible == visible) return;
    _visible = visible;
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    final returning = !_foreground && lifecycle == AppLifecycleState.resumed;
    _foreground = lifecycle == AppLifecycleState.resumed;
    _schedule(refreshOnResume: returning);
  }

  void _schedule({bool refreshOnResume = false}) {
    _timer?.cancel();
    if (!_visible ||
        !_foreground ||
        !ref.read(unionAutoRefreshEnabledProvider)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _tick(reconnect: refreshOnResume),
    );
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _tick());
  }

  void _tick({bool reconnect = false}) {
    if (!mounted || !_visible || !_foreground) return;
    final connection = ref.read(unionConnectivityProvider);
    if (connection.isLoading) return;
    final connected = connection.value ?? true;
    unawaited(
      ref
          .read(unionRefreshProvider.notifier)
          .refresh(
            widget.feeds,
            connected: connected,
            reconnect: reconnect,
            inForeground: () =>
                mounted &&
                _visible &&
                _foreground &&
                (!connected ||
                    ref.read(unionConnectivityProvider).value != false),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_visible && ref.watch(unionAutoRefreshEnabledProvider)) {
      ref.listen(unionConnectivityProvider, (previous, next) {
        if (!next.hasError &&
            (next.value == null || next.value == previous?.value))
          return;
        _tick(reconnect: previous?.value == false && next.value == true);
      });
    }
    return widget.child;
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class UnionUpdateStatus extends ConsumerWidget {
  const UnionUpdateStatus({super.key, required this.feed});

  final UnionFeed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      unionRefreshProvider.select(
        (statuses) => statuses[feed] ?? emptyUnionRead,
      ),
    );
    final time = status.lastRead;
    final text = switch (status.issue) {
      UnionReadIssue.offline when time == null =>
        'Sin conexión · pendiente de consultar',
      UnionReadIssue.offline => 'Sin conexión · mostrando datos guardados',
      UnionReadIssue.access => 'Verifique el acceso para actualizar.',
      UnionReadIssue.incompatible =>
        'Actualice la aplicación para consultar al sindicato.',
      UnionReadIssue.unavailable => 'No se pudo consultar al sindicato.',
      null when status.busy && time == null => 'Consultando al sindicato…',
      null when time != null =>
        'Actualizado a las ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(time.toLocal()), alwaysUse24HourFormat: true)}',
      null => null,
    };
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: AgroText.detail),
    );
  }
}
