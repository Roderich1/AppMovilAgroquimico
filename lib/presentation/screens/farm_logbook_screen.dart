import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/typed_reads.dart';
import '../../domain/campaign_calendar.dart' show storedLocalDay;
import '../../domain/money.dart';
import '../../domain/read_models.dart' show FarmCostRead;
import '../../operation_mode_controller.dart' show personalModeProvider;
import '../theme/agro_theme.dart';
import '../widgets/common.dart';
import '../widgets/rdm_a_list.dart' show RdmAEmpty;
import '../widgets/rdm_a_people.dart';
import '../widgets/rdm_b_ui.dart' show GroupLabel, RdmScrollPage, splitBob;
import 'ind_c_chaco_detail_screen.dart';

typedef _FarmData = ({
  Map<String, Object?> farm,
  List<Map<String, Object?>> entries,

  /// Costo aplicado del chaco en todas las campañas, del mismo informe que
  /// «Costos por chaco» (`farmCostReport`); nulo si el chaco no figura.
  FarmCostRead? cost,
});

/// Bitácora de un chaco: lo aplicado y su costo, y cada aplicación por mes
/// con sus datos (área, dosis, teórico, real, costo y lotes al desplegarla).
///
/// En modo individual `/chacos/:id` muestra el detalle del chaco (lámina
/// I-41, [IndCChacoDetailScreen]); desde él, «Ver bitácora completa» abre
/// esta bitácora con [logbook].
class FarmLogbookScreen extends ConsumerWidget {
  const FarmLogbookScreen({
    super.key,
    required this.farmId,
    this.logbook = false,
  });
  final int farmId;

  /// Fuerza la bitácora también en modo individual.
  final bool logbook;
  Future<_FarmData> _load(WidgetRef ref) async {
    final repo = ref.read(repositoryProvider);
    final farm = await repo.farmProfile(farmId);
    final entries = await repo.farmLogbook(farmId);
    final costs = await repo.farmCostReportTyped();
    return (
      farm: farm,
      entries: entries,
      cost: costs.where((row) => row.farmId == farmId).firstOrNull,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(personalModeProvider) && !logbook
      ? IndCChacoDetailScreen(farmId: farmId)
      : _logbook(context, ref);

  Widget _logbook(
    BuildContext context,
    WidgetRef ref,
  ) => FutureBuilder<_FarmData>(
    future: _load(ref),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return RdmScrollPage(
          header: const RdmAHero(title: 'Bitácora'),
          children: [
            EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(snapshot.error!),
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final d = snapshot.data!;
      final cost = d.cost;
      final perHectare = cost?.costPerHectareMinor;
      // Agrupadas por mes, en el orden de la consulta (más reciente primero).
      final months = <String, List<Map<String, Object?>>>{};
      for (final row in d.entries) {
        final day = storedLocalDay(row['applied_at']! as String);
        months.putIfAbsent(day.substring(0, 7), () => []).add(row);
      }
      return RdmScrollPage(
        header: RdmAHero(
          overline: 'Bitácora',
          title: d.farm['name'] as String,
          subtitle:
              'Bitácora · ${d.farm['owner_name']} · '
              '${formatHectares(d.farm['area_m2'] as int)}',
          children: [
            if (cost != null)
              RdmAStatPair(
                first: RdmAStatTile(
                  key: const Key('logbook-applied'),
                  label: 'Aplicado',
                  number: splitBob(cost.totalCostBobMinor).number,
                  unit: 'Bs',
                  note: 'todas las campañas',
                ),
                second: perHectare == null
                    ? const RdmAStatTile(
                        label: 'Por hectárea',
                        number: '—',
                        unit: '',
                        note: 'sin superficie',
                      )
                    : RdmAStatTile(
                        key: const Key('logbook-per-hectare'),
                        label: 'Por hectárea',
                        number: splitBob(perHectare).number,
                        unit: 'Bs',
                        note: 'todas las campañas',
                      ),
              ),
          ],
        ),
        children: [
          if (d.entries.isEmpty)
            const RdmAEmpty(
              icon: Icons.spa_outlined,
              message: 'Todavía no hay aplicaciones en este chaco.',
            )
          else
            for (final month in months.entries) ...[
              GroupLabel(rdmAMonthLabel('${month.key}-01')),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Theme(
                  // Sin las líneas que ExpansionTile dibuja al abrirse.
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: Column(
                    children: [
                      for (final (i, row) in month.value.indexed) ...[
                        if (i > 0)
                          const Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: AgroColors.line,
                          ),
                        _LogbookEntry(row: row),
                      ],
                    ],
                  ),
                ),
              ),
            ],
        ],
      );
    },
  );
}

/// Una línea de la bitácora (un producto de una aplicación). Una aplicación
/// revertida sigue en la bitácora por trazabilidad, pero no puede leerse como
/// si se hubiera aplicado: lo dice, como el historial de compras (REC-015,
/// #51).
class _LogbookEntry extends StatelessWidget {
  const _LogbookEntry({required this.row});
  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final unit = row['unit'] as String;
    final reversed = row['status'] == 'REVERSED';
    return ExpansionTile(
      tilePadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      iconColor: AgroColors.ink,
      collapsedIconColor: AgroColors.muted,
      title: Text(
        row['product_name'] as String,
        style: AgroText.value.copyWith(
          decoration: reversed ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatDate(row['applied_at'])} · ${row['campaign_name']} · '
            '${row['person_name']}'
            '${reversed ? ' · ${operationStatusLabel(row['status'])}' : ''}',
            style: AgroText.detail,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              formatQuantity(row['quantity_base'] as int, unit),
              style: AgroText.amount.copyWith(
                fontSize: 16,
                color: reversed ? AgroColors.muted : AgroColors.ink,
              ),
            ),
          ),
        ],
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedAlignment: Alignment.centerLeft,
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Área ${formatHectares(row['treated_area_m2'] as int? ?? 0)} · dosis ${formatQuantity(row['dose_base_per_ha'] as int? ?? 0, unit)}/ha\nTeórico ${formatQuantity(row['theoretical_quantity_base'] as int? ?? 0, unit)} · real ${formatQuantity(row['quantity_base'] as int, unit)} · costo ${formatBob(row['cost_bob_minor'] as int)}\nLotes ${formatFifoLots(row['fifo_lots'], unit)}',
          style: AgroText.detail.copyWith(color: AgroColors.ink),
        ),
      ],
    );
  }
}
