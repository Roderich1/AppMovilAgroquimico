// Modo individual — detalle de un chaco (lámina I-41; sesión C, 2026-11-13).
//
// Superficie del chaco, costo aplicado y costo por hectárea de la campaña
// activa (o de todas si no hay activa), planes por hacer con «Aplicar» (abre
// el formulario de aplicación desde el plan, como Planificación), las
// aplicaciones del alcance y los productos utilizados, cada uno con su unidad.
// Un plan no descuenta existencias ni genera deuda: sólo la aplicación.
// «Editar» ofrece lo que Datos permite para un chaco: cambiar el nombre y
// archivarlo (`renameCatalog`, `archiveCatalog`); la superficie no se edita
// en la app.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/ind_c_chacos_reads.dart';
import '../../domain/money.dart';
import '../../operation_mode_controller.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/catalog_dialogs.dart' show NameDialog;
import '../widgets/common.dart';
import '../widgets/ind_c_chacos_ui.dart';
import '../widgets/rdm_a_people.dart';
import '../widgets/rdm_b_ui.dart' show GroupLabel, RdmScrollPage, splitBob;
import 'farm_logbook_screen.dart';
import 'ind_c_chaco_costs_screen.dart';

class IndCChacoDetailScreen extends ConsumerStatefulWidget {
  const IndCChacoDetailScreen({super.key, required this.farmId});
  final int farmId;

  @override
  ConsumerState<IndCChacoDetailScreen> createState() =>
      _IndCChacoDetailScreenState();
}

class _IndCChacoDetailScreenState extends ConsumerState<IndCChacoDetailScreen> {
  late Future<IndCChacoDetail?> data = _load();

  Future<IndCChacoDetail?> _load() =>
      ref.read(repositoryProvider).indCChacoDetail(widget.farmId);

  void _refresh() {
    if (!mounted) return;
    setState(() {
      data = _load();
    });
  }

  Future<void> _apply(int planId) async {
    await GoRouter.maybeOf(context)
        ?.push<bool>('/aplicaciones/nueva?planId=$planId');
    _refresh();
  }

  Future<void> _edit(IndCFarm farm) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('ind-chaco-renombrar'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Cambiar el nombre'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              key: const Key('ind-chaco-archivar'),
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Archivar el chaco'),
              subtitle: const Text(
                'Deja de aparecer en listas y formularios; su historial y sus '
                'costos se conservan.',
              ),
              onTap: () => Navigator.pop(context, 'archive'),
            ),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('La superficie no se puede cambiar en la app.'),
              subtitle: Text(
                'Los costos por hectárea ya calculados dependen de ella.',
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final repo = ref.read(repositoryProvider);
    if (choice == 'rename') {
      final name = await showDialog<String?>(
        context: context,
        builder: (_) => NameDialog(
          title: 'Editar nombre',
          label: 'Nombre del chaco',
          initial: farm.name,
        ),
      );
      if (name == null || !mounted) return;
      try {
        await repo.renameCatalog('farms', farm.farmId, name);
        _refresh();
      } catch (error) {
        if (mounted) showError(context, error);
      }
      return;
    }
    final confirmed = await confirmDestructiveAction(
      context,
      title: '¿Archivar ${farm.name}?',
      detail:
          'Dejará de aparecer en las listas y formularios; su historial se '
          'conserva.',
      confirmLabel: 'Archivar',
    );
    if (!confirmed || !mounted) return;
    try {
      await repo.archiveCatalog('farms', farm.farmId);
      if (!mounted) return;
      showSuccess(context, 'Se archivó ${farm.name}.');
      final router = GoRouter.maybeOf(context);
      if (router != null && router.canPop()) {
        router.pop();
      } else {
        _refresh();
      }
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(operationModeProvider, (previous, next) {
      if (previous != next) _refresh();
    });
    return FutureBuilder<IndCChacoDetail?>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return RdmScrollPage(
            header: const RdmAHero(title: 'Chaco'),
            children: [
              EmptyState(
                icon: Icons.error_outline,
                message: friendlyError(snapshot.error!),
              ),
            ],
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = snapshot.data;
        if (d == null) {
          return const RdmScrollPage(
            header: RdmAHero(title: 'Chaco'),
            children: [
              EmptyState(
                icon: Icons.grid_on,
                message:
                    'Este chaco no existe o no pertenece al titular en el '
                    'modo individual.',
              ),
            ],
          );
        }
        return _page(d);
      },
    );
  }

  Widget _page(IndCChacoDetail d) {
    final farm = d.farm;
    final scope = indCScopeName(d.campaign);
    final perHectare = farm.costPerHectareMinor;
    final active = [
      for (final a in d.applications)
        if (!a.reversed) a,
    ];
    return RdmScrollPage(
      header: RdmAHero(
        overline: d.campaign?.name ?? 'Todas las campañas',
        title: farm.name,
        subtitle: farm.hasArea
            ? 'Superficie del chaco: ${formatHectares(farm.areaM2)}'
            : 'Falta registrar la superficie del chaco',
        subtitleKey: const Key('ind-chaco-superficie'),
        actions: [
          if (farm.active)
            FilledButton(
              key: const Key('ind-chaco-editar'),
              onPressed: () => _edit(farm),
              style: FilledButton.styleFrom(
                backgroundColor: AgroColors.inkSoft,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44),
              ),
              child: const Text('Editar'),
            ),
        ],
        children: [
          RdmAStatPair(
            first: farm.applicationCount == 0
                ? RdmAStatTile(
                    key: const Key('ind-chaco-costo'),
                    label: 'Costo aplicado',
                    number: '—',
                    unit: '',
                    note: 'sin aplicaciones · $scope',
                  )
                : RdmAStatTile(
                    key: const Key('ind-chaco-costo'),
                    label: 'Costo aplicado',
                    number: splitBob(farm.appliedCostMinor).number,
                    unit: 'Bs',
                    numberKey: const Key('ind-chaco-costo-total'),
                    note: scope,
                  ),
            second: perHectare == null
                ? RdmAStatTile(
                    key: const Key('ind-chaco-por-ha'),
                    label: 'Por ha del chaco',
                    number: 'No disponible',
                    unit: '',
                    note: farm.hasArea
                        ? 'sin aplicaciones que repartir'
                        : 'falta la superficie',
                  )
                : RdmAStatTile(
                    key: const Key('ind-chaco-por-ha'),
                    label: 'Por ha del chaco (${formatHectares(farm.areaM2)})',
                    number: splitBob(perHectare).number,
                    unit: 'Bs',
                    numberKey: const Key('ind-chaco-por-ha-valor'),
                    note: scope,
                  ),
          ),
        ],
      ),
      children: [
        if (d.plans.isNotEmpty) ...[
          GroupLabel(
            d.plans.length == 1 ? 'Plan por hacer' : 'Planes por hacer',
          ),
          for (final plan in d.plans) _PlanCard(plan: plan, onApply: _apply),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              'Un plan es una previsión: no descuenta existencias ni genera '
              'deuda hasta registrar la aplicación.',
              style: AgroText.detail,
            ),
          ),
        ],
        GroupLabel('Aplicaciones · ${active.length}'),
        if (d.applications.isEmpty)
          Card(
            child: EmptyState(
              icon: Icons.spa_outlined,
              message: d.campaign == null
                  ? 'Todavía no hay aplicaciones en este chaco.'
                  : 'Todavía no hay aplicaciones en esta campaña.',
            ),
          )
        else
          AgroGroup(
            children: [
              for (final a in d.applications)
                IndCValueRow(
                  key: Key('ind-chaco-aplicacion-${a.id}'),
                  title: _itemsTitle(a.items),
                  value: a.reversed ? 'Anulada' : formatBob(a.costMinor),
                  struck: a.reversed,
                  detail: [
                    formatDate(a.appliedAt),
                    if (d.campaign == null) a.campaignName,
                    a.treatedAreaM2 == null
                        ? 'superficie tratada sin registrar'
                        : 'superficie tratada '
                              '${formatHectares(a.treatedAreaM2!)}',
                    if (a.reversed) operationStatusLabel(a.status),
                  ].join(' · '),
                ),
            ],
          ),
        if (d.products.isNotEmpty) ...[
          GroupLabel('Productos utilizados · $scope'),
          AgroGroup(
            children: [
              for (final p in d.products)
                IndCValueRow(
                  key: Key('ind-chaco-producto-${p.productId}'),
                  title: p.name,
                  value: formatQuantity(p.quantityBase, p.unit),
                  detail: 'Costo ${formatBob(p.costMinor)}',
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            key: const Key('ind-chaco-ver-costos'),
            onPressed: () async {
              await openIndCCosts(context, campaignId: d.campaign?.id);
              _refresh();
            },
            child: const Text('Ver todos los costos'),
          ),
        ),
        Center(
          child: TextButton(
            key: const Key('ind-chaco-bitacora'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    FarmLogbookScreen(farmId: farm.farmId, logbook: true),
              ),
            ),
            child: const Text('Ver bitácora completa (lotes y dosis)'),
          ),
        ),
      ],
    );
  }

  /// «Herbicida · 2 L» o, con varios productos, «Herbicida · 2 L + 1 más».
  static String _itemsTitle(
    List<({String name, int quantityBase, String unit})> items,
  ) {
    if (items.isEmpty) return 'Aplicación';
    final first = items.first;
    final head =
        '${first.name} · ${formatQuantity(first.quantityBase, first.unit)}';
    return items.length == 1 ? head : '$head + ${items.length - 1} más';
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onApply});
  final IndCPlan plan;
  final ValueChanged<int> onApply;

  @override
  Widget build(BuildContext context) {
    final areas = {for (final i in plan.items) i.areaM2};
    final detail = [
      plan.plannedDate == null
          ? 'Sin fecha prevista'
          : 'Previsto ${formatDate(plan.plannedDate)}',
      if (areas.length == 1) formatHectares(areas.single),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AgroColors.surface,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in plan.items)
                    Text(
                      '${item.name} · '
                      '${formatQuantity(item.quantityBase, item.unit)}',
                      style: const TextStyle(
                        fontSize: 18,
                        height: 24 / 18,
                        fontWeight: FontWeight.w700,
                        color: AgroColors.ink,
                      ),
                    ),
                  Text(detail, style: AgroText.detail.copyWith(fontSize: 15)),
                ],
              ),
              FilledButton(
                key: Key('ind-chaco-aplicar-${plan.id}'),
                onPressed: () => onApply(plan.id),
                style: FilledButton.styleFrom(
                  backgroundColor: AgroColors.lime,
                  foregroundColor: AgroColors.ink,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  textStyle: const TextStyle(
                    fontFamily: AgroFonts.body,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Aplicar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
