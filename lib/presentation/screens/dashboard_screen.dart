import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/typed_reads.dart';
import '../../domain/inventory_alerts.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/installation_access.dart';
import '../../domain/operation_mode.dart';
import '../../domain/read_models.dart';
import '../../installation_access.dart';
import '../../operation_mode_controller.dart';
import '../../services/auth/access_recovery.dart';
import '../../services/auth/existing_session_providers.dart';
import '../../services/auth/existing_session_startup.dart';
import '../../services/auth/remote_session_coordinator.dart';
import '../../services/auth/remote_session_providers.dart';
import '../../services/sync/sync_providers.dart'
    show jointPurchaseNoticeProvider;
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/joint_purchase_texts.dart' show jointPurchaseNoticeText;
import '../widgets/rdm_b_ui.dart';

/// Lo que Inicio lee. Los avisos de inventario y las compras se leen aparte
/// del resumen: si fallan, Inicio sigue mostrando las cifras y dice qué no
/// pudo calcular (rediseño B, 2026-11-12).
typedef _DashboardData = ({
  DashboardSummary summary,
  List<CampaignRead> campaigns,
  InventoryAlerts? alerts,
  Object? alertsError,
  int? purchasesWithBalance,
});

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late Future<_DashboardData> future;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<_DashboardData> _load() async {
    final repo = ref.read(repositoryProvider);
    final summary = await repo.dashboard();
    final campaigns = await repo.campaignsTyped();
    InventoryAlerts? alerts;
    Object? alertsError;
    try {
      alerts = await repo.inventoryAlerts();
    } catch (error) {
      alertsError = error;
    }
    int? withBalance;
    try {
      // Compras confirmadas cuyo total supera lo pagado al proveedor: el
      // mismo saldo que «Registrar pago al proveedor» propone en Compras.
      // Sin límite de filas: con el de 200 se contarían de menos.
      final purchases = await repo.purchases(limit: 1 << 30);
      withBalance = purchases
          .where(
            (row) =>
                row['status'] == 'CONFIRMED' &&
                (row['total_bob_minor']! as int) >
                    (row['paid_bob_minor']! as int),
          )
          .length;
    } catch (_) {
      withBalance = null;
    }
    return (
      summary: summary,
      campaigns: campaigns,
      alerts: alerts,
      alertsError: alertsError,
      purchasesWithBalance: withBalance,
    );
  }

  void _refresh() {
    final next = _load();
    setState(() {
      future = next;
    });
  }

  /// Acceso directo al formulario (piloto X01): al volver con la compra
  /// guardada se avisa con un mensaje específico y se recarga el resumen. Un
  /// borrador tardío devuelve `false` y no se anuncia como confirmado.
  Future<void> _newPurchase() async {
    final saved = await context.push<bool>('/compras/nueva');
    if (!mounted) return;
    if (saved == true) {
      _refresh();
      showSuccess(context, 'Compra guardada.');
    }
  }

  Future<void> _newApplication() async {
    final active = await ref.read(repositoryProvider).activeCampaign();
    if (!mounted) return;
    if (active == null) {
      showError(
        context,
        // B1: Campañas se abre desde la campaña de la cabecera de Inicio.
        'Active una campaña antes de registrar aplicaciones: toque la '
        'campaña arriba en Inicio.',
      );
      return;
    }
    final saved = await context.push<bool>('/aplicaciones/nueva');
    if (!mounted) return;
    if (saved == true) {
      _refresh();
      showSuccess(context, 'Aplicación guardada.');
    }
  }

  /// Abre una pantalla de Inicio y, al volver, recarga las cifras: lo que se
  /// haya registrado allí cambia los avisos y los saldos.
  ///
  /// Recibe la navegación ya iniciada (`context.push` con la ruta escrita,
  /// para que la guarda de rutas sin origen la encuentre).
  Future<void> _openAndRefresh(Future<Object?> navigation) async {
    await navigation;
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) =>
      _build(context, ref.watch(effectiveLocalSessionProvider));

  Widget _build(
    BuildContext context,
    ExistingSessionStartupState existingSession,
  ) {
    final personal = ref.watch(operationModeProvider) == OperationMode.personal;
    return FutureBuilder<_DashboardData>(
      future: future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        // Tirar hacia abajo actualiza las cifras (el botón «Actualizar» dejó
        // su lugar al engranaje de Ajustes, B1). Al volver de cualquier
        // pantalla abierta desde Inicio también se actualizan.
        return RefreshIndicator(
          onRefresh: () async {
            _refresh();
            await future.then((_) {}, onError: (_) {});
          },
          child: RdmScrollPage(
            header: _HomeHeader(
              data: data,
              personal: personal,
              loading: data == null && !snapshot.hasError,
              onSettings: () => _openAndRefresh(context.push('/mas')),
              onCampaigns: () => _openAndRefresh(context.push('/campanas')),
            ),
            children: [
              // Los avisos de sesión y de acceso, y los accesos principales
              // (piloto X01), no dependen del resumen: se muestran aunque los
              // datos tarden o fallen. «Enviar al sindicato» abre la pantalla
              // de sincronización y no publica nada por sí solo.
              _SessionArea(existingSession, top: true),
              const _InstallationAccessNotice(),
              const _JointPurchaseNotice(),
              const SizedBox(height: 4),
              ActionTileRow(
                tiles: [
                  ActionTile(
                    key: const Key('home-registrar-compra'),
                    icon: Icons.shopping_bag_outlined,
                    label: 'Registrar compra',
                    onTap: _newPurchase,
                    minHeight: 108,
                  ),
                  ActionTile(
                    key: const Key('home-registrar-aplicacion'),
                    icon: Icons.spa_outlined,
                    label: 'Registrar aplicación',
                    onTap: _newApplication,
                    tone: ActionTileTone.ink,
                    minHeight: 108,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              AgroGroup(
                children: [
                  LinkRow(
                    key: const Key('home-ver-cuanto-queda'),
                    icon: Icons.inventory_2_outlined,
                    title: 'Ver cuánto queda',
                    onTap: () => context.go('/inventario'),
                  ),
                  LinkRow(
                    key: const Key('home-enviar-sindicato'),
                    icon: Icons.cloud_upload_outlined,
                    title: 'Enviar al sindicato',
                    onTap: () => context.push('/sincronizacion'),
                  ),
                ],
              ),
              if (snapshot.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: NoticeBox(
                    key: const Key('home-load-error'),
                    tone: NoticeTone.danger,
                    icon: Icons.error_outline,
                    text: friendlyError(snapshot.error!),
                  ),
                )
              else if (data != null) ...[
                const SizedBox(height: 18),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('Para atender', style: AgroText.h2),
                ),
                _AttentionList(data: data, onOpen: _openAndRefresh),
                // E-15: del libro de cuentas, sin el titular (no es deudor de
                // sí mismo) ni el ADMIN. En propio no hay cuentas por cobrar.
                if (!personal && data.summary.topBalances.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
                    child: Text('Principales saldos', style: AgroText.h2),
                  ),
                  AgroGroup(
                    key: const Key('home-top-balances'),
                    children: [
                      for (final row in data.summary.topBalances.take(5))
                        LinkRow(
                          title: row.name,
                          titleStyle: const TextStyle(
                            fontSize: 15,
                            height: 20 / 15,
                            fontWeight: FontWeight.w700,
                            color: AgroColors.ink,
                          ),
                          subtitle: row.role == 'FAMILY'
                              ? 'Familiar'
                              : 'Tercero',
                          trailing: Text(
                            formatBob(row.balanceMinor),
                            style: AgroText.amount,
                          ),
                          onTap: () => _openAndRefresh(
                            context.push('/personas/${row.personId}'),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
              _SessionArea(existingSession, top: false),
            ],
          ),
        );
      },
    );
  }
}

bool _allowsRemote(ExistingSessionStartupState startup) =>
    startup == ExistingSessionStartupState.localSessionAvailable ||
    startup == ExistingSessionStartupState.localSessionExpired;

/// Un solo mensaje de estado de acceso (#83). Antes se mostraban a la vez el
/// estado de arranque («aún no fue verificado») y el remoto («verificado para
/// esta sesión»). El de arranque vale mientras no haya actividad remota; un
/// guard en cuarentena ya exige reautenticar, aunque no haya intento en este
/// proceso.
String sessionStatusMessage(
  ExistingSessionStartupState startup,
  RemoteSessionState remote, {
  required AsyncValue<bool> guard,
}) {
  if (!_allowsRemote(startup)) return startup.safeMessage ?? '';
  if (remote.phase != RemoteSessionPhase.idle) return remote.safeMessage;
  if (guard.hasError) {
    return const RemoteSessionState(RemoteSessionPhase.guardUnavailable)
        .safeMessage;
  }
  if (guard.asData?.value == true) {
    return const RemoteSessionState(RemoteSessionPhase.requiresReauthentication)
        .safeMessage;
  }
  return startup.safeMessage!;
}

/// Bloqueos de la sesión: con ellos no se puede trabajar en línea y la
/// salida (volver a autenticar) va primero.
bool _remoteBlocked(AsyncValue<bool> guard, RemoteSessionState remote) =>
    guard.asData?.value != false ||
    remote.phase == RemoteSessionPhase.requiresReauthentication ||
    remote.phase == RemoteSessionPhase.outcomeUnknown ||
    remote.phase == RemoteSessionPhase.registrationRejected ||
    remote.phase == RemoteSessionPhase.guardUnavailable;

/// Estado y acciones de la sesión (F03, #83): no dependen del resumen.
///
/// Rediseño B: lo que impide trabajar en línea (activar, recuperar acceso,
/// volver a autenticar, un estado ilegible) va arriba de Inicio, con borde
/// de atención; el estado de rutina («aún no fue verificado» y «Verificar
/// acceso en línea») va al final, en «Cuenta en línea». Son los mismos
/// textos, claves y acciones; sólo cambia el lugar. Se monta dos veces
/// ([top] verdadero y falso) y cada una se dibuja sólo en su lugar.
class _SessionArea extends ConsumerWidget {
  const _SessionArea(this.startup, {required this.top});

  final ExistingSessionStartupState startup;
  final bool top;

  static const _status = TextStyle(
    fontSize: 15,
    height: 21 / 15,
    color: AgroColors.ink,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recoverAsOwner =
        accessRecoveryModeFor(ref.watch(installationAccessProvider), startup) ==
        AccessRecoveryMode.signInAsOwner;
    final allowsRemote = _allowsRemote(startup);
    // Como antes del rediseño, el guard y el estado remoto sólo se leen
    // con una sesión local que permite trabajar en línea.
    final guard = allowsRemote
        ? ref.watch(refreshGuardStateProvider)
        : const AsyncValue<bool>.data(false);
    final remote = allowsRemote
        ? ref.watch(remoteSessionProvider)
        : const RemoteSessionState(RemoteSessionPhase.idle);
    final blocked = allowsRemote && _remoteBlocked(guard, remote);
    final urgent =
        recoverAsOwner ||
        startup == ExistingSessionStartupState.noLocalSession ||
        (!allowsRemote && startup.safeMessage != null) ||
        (allowsRemote && !guard.isLoading && blocked);
    if (urgent != top) return const SizedBox.shrink();
    final children = <Widget>[
      // F03: con titular vinculado y sesión ausente o ilegible, la entrada
      // es «Recuperar acceso» (mismo Member y tenant), nunca una activación
      // libre que pudiera guardar la sesión de otra cuenta.
      if (startup == ExistingSessionStartupState.noLocalSession &&
          !recoverAsOwner)
        OutlinedButton.icon(
          key: const Key('open-first-activation'),
          onPressed: () => context.push('/activar'),
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('Activar cuenta en línea'),
        )
      else if (allowsRemote)
        Text(
          sessionStatusMessage(startup, remote, guard: guard),
          key: const Key('local-session-status'),
          style: _status,
        )
      else if (startup.safeMessage != null)
        Text(
          startup.safeMessage!,
          key: const Key('local-session-status'),
          style: _status,
        ),
      if (recoverAsOwner)
        OutlinedButton.icon(
          key: const Key('open-access-recovery'),
          onPressed: () => context.push('/recuperar'),
          icon: const Icon(Icons.key_outlined),
          label: const Text('Recuperar acceso'),
        ),
      if (allowsRemote)
        if (guard.isLoading)
          const Text(
            'Comprobando protección local de la sesión…',
            style: AgroText.detail,
          )
        else if (blocked)
          OutlinedButton.icon(
            key: const Key('open-reauthentication'),
            onPressed: remote.isBusy ? null : () => context.push('/reauth'),
            icon: const Icon(Icons.lock_reset_outlined),
            label: const Text('Volver a autenticar'),
          )
        else
          OutlinedButton.icon(
            key: const Key('verify-online-access'),
            onPressed: remote.isBusy
                ? null
                : () => ref.read(remoteSessionProvider.notifier).verifyOnline(),
            icon: const Icon(Icons.cloud_done_outlined),
            label: const Text('Verificar acceso en línea'),
          ),
      // «PIN del titular» pasó a Más y «Sincronización con el sindicato»
      // es el acceso «Enviar al sindicato» (piloto X01): aquí quedan sólo
      // los avisos y acciones de la sesión.
    ];
    final box = Container(
      key: Key(top ? 'home-session-urgent' : 'home-session-routine'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AgroColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: urgent ? Border.all(color: AgroColors.caution, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
      ),
    );
    if (top) {
      return Padding(padding: const EdgeInsets.only(bottom: 10), child: box);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Text('Cuenta en línea', style: AgroText.h2),
        ),
        box,
      ],
    );
  }
}

/// «1 lote vencido», «2 lotes vencidos».
String _count(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// Cabecera oscura de Inicio: campaña activa, la cifra principal según el
/// modo de uso y las cifras de compras y pagos.
///
/// Compartido: «Por cobrar» es la suma de lo que deben familias y terceros
/// (D-04: Σ max(0, saldo neto)); cada grupo y lo que queda a su favor se
/// nombran sólo si tienen importe, para no mostrar deudas de terceros como
/// si siempre existieran. Propio: no hay cuentas por cobrar (E-15), así que
/// la cifra principal son las compras; «Por cobrar» sólo aparece si quedara
/// algún saldo. Las cifras son de todas las campañas (`dashboard()` no
/// filtra por campaña) y así se dice.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.data,
    required this.personal,
    required this.loading,
    required this.onSettings,
    required this.onCampaigns,
  });

  final _DashboardData? data;
  final bool personal;
  final bool loading;
  final VoidCallback onSettings;
  final VoidCallback onCampaigns;

  static const _muted = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    color: AgroColors.onInkMuted,
  );
  static const _onInk = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    color: AgroColors.onInk,
  );

  @override
  Widget build(BuildContext context) {
    final data = this.data;
    final active = data?.campaigns
        .where((campaign) => campaign.isActive)
        .firstOrNull;
    return Container(
      decoration: const BoxDecoration(
        color: AgroColors.ink,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      header: true,
                      label: 'Inicio',
                      child: const Text(
                        'Agrocuentas',
                        key: Key('page-frame-title'),
                        style: TextStyle(
                          fontFamily: AgroFonts.display,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (data != null)
                      Semantics(
                        label: active == null
                            ? 'Sin campaña activa'
                            : 'Campaña activa: ${active.name}',
                        excludeSemantics: true,
                        button: true,
                        hint: 'Abre Campañas',
                        child: Material(
                          color: AgroColors.inkSoft,
                          shape: const StadiumBorder(),
                          child: InkWell(
                            key: const Key('home-active-campaign'),
                            customBorder: const StadiumBorder(),
                            onTap: onCampaigns,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 40),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        active?.name ?? 'Sin campaña activa',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AgroColors.onInk,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.expand_more,
                                      size: 18,
                                      color: AgroColors.onInk,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CircleIconButton(
                key: const Key('home-settings'),
                icon: Icons.settings_outlined,
                tooltip: 'Ajustes y datos',
                onPressed: onSettings,
                background: AgroColors.inkSoft,
                foreground: AgroColors.onInk,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(color: AgroColors.lime),
              ),
            )
          else if (data != null) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: personal ? _personalHero(data) : _sharedHero(data),
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, thickness: 1, color: AgroColors.inkSoft),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Figures(items: _figures(data.summary)),
            ),
            const SizedBox(height: 10),
            const Text(
              'Cifras de todas las campañas',
              key: Key('home-figures-scope'),
              style: TextStyle(fontSize: 12, color: AgroColors.onInkMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sharedHero(_DashboardData data) {
    final s = data.summary;
    final total = s.familyReceivableMinor + s.thirdPartyReceivableMinor;
    final split = splitBob(total);
    final family = s.familyReceivableMinor > 0 || s.familyCreditMinor > 0;
    final third =
        s.thirdPartyReceivableMinor > 0 || s.thirdPartyCreditMinor > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Por cobrar', style: _muted),
        BigFigure(
          numberKey: const Key('home-receivable-total'),
          number: split.number,
          unit: split.unit,
          size: 56,
          color: AgroColors.lime,
        ),
        const SizedBox(height: 4),
        if (!family && !third)
          const Text(
            'Sin saldos por cobrar',
            key: Key('home-receivable-none'),
            style: _onInk,
          )
        else
          Wrap(
            spacing: 14,
            runSpacing: 2,
            children: [
              if (family)
                Text(
                  'Familias ${formatBob(s.familyReceivableMinor)}',
                  key: const Key('home-receivable-family'),
                  style: _onInk,
                ),
              if (third)
                Text(
                  'Terceros ${formatBob(s.thirdPartyReceivableMinor)}',
                  key: const Key('home-receivable-third'),
                  style: _onInk,
                ),
            ],
          ),
        // D-04: lo que queda a favor se dice aparte, sin restarlo.
        if (s.familyCreditMinor > 0)
          Text(
            'A favor de familias: ${formatBob(s.familyCreditMinor).trim()}',
            key: const Key('home-credit-family'),
            style: _muted,
          ),
        if (s.thirdPartyCreditMinor > 0)
          Text(
            'A favor de terceros: '
            '${formatBob(s.thirdPartyCreditMinor).trim()}',
            key: const Key('home-credit-third'),
            style: _muted,
          ),
      ],
    );
  }

  Widget _personalHero(_DashboardData data) {
    final split = splitBob(data.summary.purchasesBobMinor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Compras', style: _muted),
        BigFigure(
          numberKey: const Key('home-purchases-total'),
          number: split.number,
          unit: split.unit,
          size: 56,
          color: AgroColors.lime,
        ),
      ],
    );
  }

  List<({String label, String value, Key key})> _figures(DashboardSummary s) {
    final receivable = s.familyReceivableMinor + s.thirdPartyReceivableMinor;
    return [
      if (!personal)
        (
          label: 'Compras',
          value: splitBob(s.purchasesBobMinor).number,
          key: const Key('home-figure-purchases'),
        ),
      (
        label: 'Pagado a proveedores',
        value: splitBob(s.providerPaidMinor).number,
        key: const Key('home-figure-provider-paid'),
      ),
      // En propio, los pagos recibidos y lo por cobrar sólo si hay importe
      // (datos de antes del cambio de modo); en compartido, siempre.
      if (!personal || s.receivedMinor != 0)
        (
          label: 'Pagos recibidos',
          value: splitBob(s.receivedMinor).number,
          key: const Key('home-figure-received'),
        ),
      if (personal && receivable > 0)
        (
          label: 'Por cobrar',
          value: splitBob(receivable).number,
          key: const Key('home-figure-receivable'),
        ),
    ];
  }
}

/// Cifras pequeñas de la cabecera, en columnas. Si con la letra del teléfono
/// una etiqueta no cabe sin partir una palabra, se quitan columnas.
class _Figures extends StatelessWidget {
  const _Figures({required this.items});
  final List<({String label, String value, Key key})> items;

  static const _label = TextStyle(
    fontFamily: AgroFonts.body,
    fontSize: 12,
    height: 16 / 12,
    color: AgroColors.onInkMuted,
  );
  static const _value = TextStyle(
    fontFamily: AgroFonts.body,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final widest = [
        for (final item in items) ...[
          ...item.label.split(' ').map((w) => measureText(context, w, _label)),
          measureText(context, '${item.value} Bs', _value),
        ],
      ].fold(0.0, math.max);
      var columns = math.max(1, items.length);
      double widthFor(int n) => (constraints.maxWidth - (n - 1) * 10) / n;
      while (columns > 1 && widthFor(columns) < widest + 4) {
        columns--;
      }
      final width = widthFor(columns);
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final item in items)
            SizedBox(
              width: width,
              child: Semantics(
                label: '${item.label}: ${item.value} Bs',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label, style: _label),
                    Text('${item.value} Bs', key: item.key, style: _value),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// «Para atender»: sólo lo que hoy pide una acción y que el teléfono ya
/// calcula. Los avisos de vencimiento cuentan **lotes**; los de existencia
/// baja, **productos** (en el total o por responsable, como en Avisos).
class _AttentionList extends StatelessWidget {
  const _AttentionList({required this.data, required this.onOpen});

  final _DashboardData data;
  final void Function(Future<Object?> navigation) onOpen;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void avisos() => onOpen(context.push('/inventario/avisos'));
    final alerts = data.alerts;
    if (data.alertsError != null) {
      rows.add(
        LinkRow(
          key: const Key('home-attention-alerts-error'),
          dot: DotTone.danger,
          title: 'No se pudieron calcular los avisos de inventario',
          onTap: avisos,
        ),
      );
    } else if (alerts != null) {
      if (alerts.clockLooksBehind) {
        rows.add(
          LinkRow(
            key: const Key('home-attention-clock'),
            dot: DotTone.danger,
            title: 'Revise la fecha del teléfono: los avisos dependen de ella',
            onTap: avisos,
          ),
        );
      }
      final expiry = [
        if (alerts.expired.isNotEmpty)
          _count(alerts.expired.length, 'lote vencido', 'lotes vencidos'),
        if (alerts.dueToday.isNotEmpty)
          _count(alerts.dueToday.length, 'lote vence hoy', 'lotes vencen hoy'),
      ];
      if (expiry.isNotEmpty) {
        rows.add(
          LinkRow(
            key: const Key('home-attention-expiry'),
            dot: DotTone.danger,
            title: expiry.join(' · '),
            onTap: avisos,
          ),
        );
      }
      if (alerts.near.isNotEmpty) {
        rows.add(
          LinkRow(
            key: const Key('home-attention-near'),
            dot: DotTone.caution,
            title: _count(
              alerts.near.length,
              'lote por vencer',
              'lotes por vencer',
            ),
            onTap: avisos,
          ),
        );
      }
      final lowTotal = alerts.lowStock.where((a) => a.line.isTotal).length;
      final lowPerson = alerts.lowStock.length - lowTotal;
      final low = [
        if (lowTotal > 0)
          '${_count(lowTotal, 'producto', 'productos')} en el total',
        if (lowPerson > 0)
          '${_count(lowPerson, 'existencia', 'existencias')} por responsable',
      ];
      if (low.isNotEmpty) {
        rows.add(
          LinkRow(
            key: const Key('home-attention-low'),
            dot: DotTone.caution,
            title: 'Queda poco: ${low.join(' · ')}',
            onTap: avisos,
          ),
        );
      }
    }
    final withBalance = data.purchasesWithBalance;
    if (withBalance == null) {
      rows.add(
        LinkRow(
          key: const Key('home-attention-purchases-error'),
          dot: DotTone.danger,
          title: 'No se pudo revisar el saldo de las compras',
          onTap: () => onOpen(context.push('/compras')),
        ),
      );
    } else if (withBalance > 0) {
      rows.add(
        LinkRow(
          key: const Key('home-attention-provider-balance'),
          dot: DotTone.caution,
          title:
              '${_count(withBalance, 'compra', 'compras')} con saldo por '
              'pagar al proveedor',
          onTap: () => onOpen(context.push('/compras')),
        ),
      );
    }
    if (rows.isEmpty) {
      rows.add(
        const LinkRow(
          key: Key('home-attention-none'),
          dot: DotTone.ok,
          title: 'Nada pendiente por ahora',
        ),
      );
    }
    return AgroGroup(children: rows);
  }
}

/// E2-D15: «Nueva convocatoria: {nombre} · cierra el {fecha}» mientras haya
/// una convocatoria abierta que no se abrió en este teléfono. Una sola
/// consulta indexada; sin push y sin red. Tocarlo abre la convocatoria, que
/// queda vista y el aviso desaparece.
class _JointPurchaseNotice extends ConsumerWidget {
  const _JointPurchaseNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(jointPurchaseNoticeProvider).value;
    if (notice == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AgroColors.warnBg,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: const Key('joint-purchase-notice'),
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push(
            notice.total > 1
                ? '/compras-conjuntas'
                : '/compras-conjuntas/${notice.callId}',
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                const IconCircle(
                  icon: Icons.campaign_outlined,
                  background: AgroColors.warnInk,
                  foreground: AgroColors.warnBg,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    jointPurchaseNoticeText(notice),
                    style: const TextStyle(
                      fontSize: 15,
                      height: 20 / 15,
                      fontWeight: FontWeight.w700,
                      color: AgroColors.warnInk,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: AgroColors.warnInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Aviso de la política de activación (#76) cuando la instalación opera en
/// compatibilidad o sin sesión, y acceso a la elección explícita del titular.
class _InstallationAccessNotice extends ConsumerWidget {
  const _InstallationAccessNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(installationAccessProvider);
    if (access == null || access == InstallationAccessState.activated) {
      return const SizedBox.shrink();
    }
    final scope = ref.read(installationAccessProvider.notifier).sessionScope;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(access.message, key: const Key('installation-access-notice')),
          if (access.allowsOwnerBinding && scope != null)
            TextButton.icon(
              key: const Key('dashboard-choose-owner'),
              onPressed: () => context.push('/titular'),
              icon: const Icon(Icons.person_pin_outlined),
              label: const Text('Elegir titular'),
            ),
        ],
      ),
    );
  }
}
