// Modo individual — «Costos» de Chacos (lámina I-42; sesión C, 2026-11-13).
//
// Costo de productos aplicados por chaco, por producto y por campaña, con los
// mismos criterios que los informes «Costo por chaco» y «Costo por producto»
// (aplicaciones no revertidas). No incluye compras ni el valor de lo que sigue
// en el almacén. El costo por hectárea se calcula sobre la superficie del
// chaco; sin superficie o sin aplicaciones es «No disponible», nunca cero.
// La exportación abre Reportes (Excel o PDF) con el informe y la campaña.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/ind_c_chacos_reads.dart';
import '../../domain/money.dart';
import '../../domain/reports/report_composer.dart' show ReportKind;
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/ind_c_chacos_ui.dart';
import '../widgets/rdm_b_ui.dart' show RdmBackButton, RdmScrollPage, splitBob;

/// Pestañas de «Costos».
enum IndCCostView { farm, product, campaign }

/// Abre «Costos» (`/chacos/costos`) apilado: Atrás vuelve a donde se abrió.
Future<void> openIndCCosts(BuildContext context, {int? campaignId}) =>
    context.push<void>(
      campaignId == null
          ? '/chacos/costos'
          : '/chacos/costos?campana=$campaignId',
    );

typedef _CostsData = ({
  IndCChacos chacos,
  List<IndCProductCost> products,
  List<IndCCampaignCost> campaigns,
});

class IndCChacoCostsScreen extends ConsumerStatefulWidget {
  const IndCChacoCostsScreen({
    super.key,
    this.initialCampaignId,
    this.initialView = IndCCostView.farm,
  });

  /// Campaña del alcance; nulo = todas las campañas.
  final int? initialCampaignId;
  final IndCCostView initialView;

  @override
  ConsumerState<IndCChacoCostsScreen> createState() =>
      _IndCChacoCostsScreenState();
}

class _IndCChacoCostsScreenState extends ConsumerState<IndCChacoCostsScreen> {
  late int? campaignId = widget.initialCampaignId;
  late IndCCostView view = widget.initialView;
  late Future<_CostsData> data = _load();

  Future<_CostsData> _load() async {
    final repo = ref.read(repositoryProvider);
    return (
      chacos: await repo.indCChacos(campaignId: campaignId),
      products: await repo.indCProductCosts(campaignId: campaignId),
      campaigns: await repo.indCCampaignCosts(),
    );
  }

  void _setCampaign(int? next) => setState(() {
    campaignId = next;
    data = _load();
  });

  void _export() {
    final kind = switch (view) {
      IndCCostView.farm => ReportKind.farmCost,
      IndCCostView.product => ReportKind.productCost,
      IndCCostView.campaign => ReportKind.campaignSummary,
    };
    GoRouter.maybeOf(context)?.push(
      '/reportes?tipo=${kind.name}'
      '${campaignId == null ? '' : '&campana=$campaignId'}',
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_CostsData>(
    future: data,
    builder: (context, snapshot) {
      final loaded = snapshot.data;
      return RdmScrollPage(
        children: [
          _TopBar(
            campaigns: loaded?.chacos.scope.campaigns ?? const [],
            campaignId: campaignId,
            onCampaign: _setCampaign,
          ),
          const SizedBox(height: 12),
          // Rótulos cortos: «Por producto» no cabe en un tercio a 360–390 dp
          // y el selector se apilaría (regla de `SegmentToggle`).
          SegmentToggle<IndCCostView>(
            semanticLabel: 'Costos por',
            options: const [
              ToggleOption(
                IndCCostView.farm,
                'Chacos',
                key: Key('ind-costos-por-chaco'),
              ),
              ToggleOption(
                IndCCostView.product,
                'Productos',
                key: Key('ind-costos-por-producto'),
              ),
              ToggleOption(
                IndCCostView.campaign,
                'Campañas',
                key: Key('ind-costos-por-campana'),
              ),
            ],
            selected: view,
            onChanged: (next) => setState(() => view = next),
          ),
          const SizedBox(height: 16),
          if (snapshot.hasError)
            EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(snapshot.error!),
            )
          else if (loaded == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _hero(loaded),
            const SizedBox(height: 16),
            ...switch (view) {
              IndCCostView.farm => _byFarm(loaded),
              IndCCostView.product => _byProduct(loaded),
              IndCCostView.campaign => _byCampaign(loaded),
            },
            const SizedBox(height: 16),
            SecondaryActionButton(
              key: const Key('ind-costos-exportar'),
              label: 'Exportar en Excel o PDF',
              icon: Icons.download,
              onPressed: _export,
            ),
            const SizedBox(height: 6),
            Text(
              'Abre Reportes con «${_reportName(view)}» de '
              '${indCScopeName(loaded.chacos.campaign)}.',
              style: AgroText.detail,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      );
    },
  );

  static String _reportName(IndCCostView view) => switch (view) {
    IndCCostView.farm => 'Costo por chaco',
    IndCCostView.product => 'Costo por producto',
    IndCCostView.campaign => 'Resumen de campaña',
  };

  Widget _hero(_CostsData loaded) {
    final chacos = loaded.chacos;
    final count = chacos.applicationCount;
    final scope = indCScopeName(chacos.campaign);
    return IndCDarkFigureCard(
      key: const Key('ind-costos-hero'),
      label: 'Costo de productos aplicados · $scope',
      number: count == 0 ? null : splitBob(chacos.appliedCostMinor).number,
      numberKey: const Key('ind-costos-total'),
      emptyText: 'Todavía no hay aplicaciones',
      note: count == 0
          ? 'Las compras y lo que sigue en el almacén no son costo aplicado.'
          : '$count ${count == 1 ? 'aplicación' : 'aplicaciones'}. No '
                'incluye compras ni lo que sigue en el almacén.',
    );
  }

  List<Widget> _byFarm(_CostsData loaded) {
    final chacos = loaded.chacos;
    if (chacos.farms.isEmpty) {
      return const [
        Card(
          child: EmptyState(
            icon: Icons.grid_on,
            message: 'Todavía no hay chacos registrados.',
          ),
        ),
      ];
    }
    return [
      for (final farm in chacos.farms)
        IndCFarmCostCard(
          farm: farm,
          showOwner: !chacos.scope.personal,
          onTap: () =>
              GoRouter.maybeOf(context)?.push('/chacos/${farm.farmId}'),
        ),
    ];
  }

  List<Widget> _byProduct(_CostsData loaded) {
    if (loaded.products.isEmpty) {
      return const [
        Card(
          child: EmptyState(
            icon: Icons.science_outlined,
            message: 'Sin productos aplicados en este alcance.',
          ),
        ),
      ];
    }
    // Cantidades por unidad: nunca se suman litros con kilos.
    final byUnit = <String, int>{};
    for (final row in loaded.products) {
      byUnit[row.unit] = (byUnit[row.unit] ?? 0) + row.quantityBase;
    }
    return [
      AgroGroup(
        children: [
          for (final row in loaded.products)
            IndCValueRow(
              key: Key('ind-costo-producto-${row.productId}'),
              title: row.name,
              value: formatBob(row.costMinor),
              detail:
                  '${formatQuantity(row.quantityBase, row.unit)} · en '
                  '${row.applicationCount} '
                  '${row.applicationCount == 1 ? 'aplicación' : 'aplicaciones'}',
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        'Cantidad aplicada por unidad: '
        '${[for (final e in byUnit.entries) formatQuantity(e.value, e.key)].join(' · ')}.',
        key: const Key('ind-costos-por-unidad'),
        style: AgroText.detail,
      ),
    ];
  }

  List<Widget> _byCampaign(_CostsData loaded) {
    if (loaded.campaigns.isEmpty) {
      return const [
        Card(
          child: EmptyState(
            icon: Icons.calendar_month_outlined,
            message: 'Todavía no hay campañas registradas.',
          ),
        ),
      ];
    }
    return [
      AgroGroup(
        children: [
          for (final row in loaded.campaigns)
            IndCValueRow(
              key: Key('ind-costo-campana-${row.campaign.id}'),
              title: row.campaign.name,
              value: row.applicationCount == 0
                  ? 'Sin aplicaciones'
                  : formatBob(row.costMinor),
              detail: [
                _campaignStatus(row.campaign.status),
                if (row.applicationCount > 0)
                  '${row.applicationCount} '
                      '${row.applicationCount == 1 ? 'aplicación' : 'aplicaciones'}',
              ].join(' · '),
              trailing: const Icon(
                Icons.chevron_right,
                color: AgroColors.muted,
              ),
              // Ver esa campaña por chaco.
              onTap: () {
                _setCampaign(row.campaign.id);
                setState(() => view = IndCCostView.farm);
              },
            ),
        ],
      ),
    ];
  }

  static String _campaignStatus(String status) => switch (status) {
    'ACTIVE' => 'Activa',
    'CLOSED' => 'Cerrada',
    'PLANNED' => 'Planificada',
    _ => status,
  };
}

/// «← Costos   [Invierno 2026 ▾]».
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.campaigns,
    required this.campaignId,
    required this.onCampaign,
  });

  final List<IndCCampaign> campaigns;
  final int? campaignId;
  final ValueChanged<int?> onCampaign;

  @override
  Widget build(BuildContext context) {
    final current =
        campaigns.where((c) => c.id == campaignId).firstOrNull?.name ??
        'Todas las campañas';
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RdmBackButton(),
            Semantics(
              header: true,
              child: const Text(
                'Costos',
                key: Key('page-frame-title'),
                style: TextStyle(
                  fontFamily: AgroFonts.display,
                  fontSize: 30,
                  height: 36 / 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: AgroColors.ink,
                ),
              ),
            ),
          ],
        ),
        PopupMenuButton<int>(
          key: const Key('ind-costos-campana'),
          tooltip: 'Elegir campaña',
          // -1 = todas las campañas.
          onSelected: (value) => onCampaign(value < 0 ? null : value),
          itemBuilder: (_) => [
            const PopupMenuItem(value: -1, child: Text('Todas las campañas')),
            for (final campaign in campaigns)
              PopupMenuItem(value: campaign.id, child: Text(campaign.name)),
          ],
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.fromLTRB(18, 10, 14, 10),
            decoration: BoxDecoration(
              color: AgroColors.surface,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    current,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AgroColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.expand_more, color: AgroColors.ink),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
