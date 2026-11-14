import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/rdm_a_list.dart';

class PlanningScreen extends ConsumerStatefulWidget {
  const PlanningScreen({super.key});
  @override
  ConsumerState<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends ConsumerState<PlanningScreen> {
  late Future<List<Map<String, Object?>>> future;
  int? campaignFilter;

  /// La vista operativa muestra **planes pendientes** (UIBUG-045).
  ///
  /// Un plan aplicado ya no se puede volver a usar, así que dejarlo en la
  /// lista principal sólo estorba: con los años serían decenas de filas
  /// muertas. No se borran —son parte de la trazabilidad—; se consultan con
  /// este interruptor.
  bool showApplied = false;

  @override
  void initState() {
    super.initState();
    future = ref.read(repositoryProvider).plans();
  }

  void refresh() {
    final next = ref
        .read(repositoryProvider)
        .plans(includeApplied: showApplied);
    setState(() {
      future = next;
    });
  }

  /// Abre el formulario de aplicación precargado con el plan y **recarga al
  /// volver**.
  ///
  /// Sin la recarga la fila seguía diciendo "pendiente" y ofreciendo "Aplicar"
  /// después de haberse aplicado: el estado del plan pasó a decidir qué muestra
  /// esta lista, así que la lista tiene que releerlo. Detectado en el Pixel 8
  /// durante la regresión final.
  Future<void> applyPlan(int planId) async {
    await context.push<bool>('/aplicaciones/nueva?planId=$planId');
    if (mounted) refresh();
  }

  Future<void> add() async {
    final active = await ref.read(repositoryProvider).activeCampaign();
    if (!mounted) return;
    if (active == null) {
      showError(context, 'Active una campaña antes de planificar.');
      return;
    }
    final saved = await context.push<bool>('/planificacion/nueva');
    if (saved == true && mounted) refresh();
  }

  @override
  Widget build(BuildContext context) => RdmAListPage(
    title: 'Planificación',
    // Desde B1 no hay «+ Registrar» flotante aquí: el botón dice qué crea.
    action: RdmARegisterButton(
      key: const Key('planning-new'),
      label: 'Nuevo plan',
      onPressed: add,
    ),
    child: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, s) {
        if (s.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(s.error!),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final groups = <int, List<Map<String, Object?>>>{};
        for (final row in s.data!) {
          groups.putIfAbsent(row['plan_id'] as int, () => []).add(row);
        }
        final visible = groups.entries
            .where(
              (e) =>
                  campaignFilter == null ||
                  e.value.first['campaign_id'] == campaignFilter,
            )
            .toList();
        final campaigns = {
          for (final row in s.data!)
            row['campaign_id'] as int: row['campaign_name'] as String,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // La necesidad declarada al sindicato es otra cosa que un plan
            // (F06 §3): una intención expresa, no un cálculo de dosis.
            AgroGroup(
              children: [
                ValueRow(
                  key: const Key('open-declared-needs'),
                  label: 'Para el sindicato',
                  value: 'Necesidad declarada',
                  onTap: () => context.push('/planificacion/necesidades'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              initialValue: campaignFilter,
              decoration: const InputDecoration(labelText: 'Campaña'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas')),
                for (final e in campaigns.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => campaignFilter = v),
            ),
            const SizedBox(height: 8),
            // Acceso secundario y discreto al histórico: no compite con la
            // lista, pero el plan aplicado sigue siendo consultable.
            Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                selected: showApplied,
                onSelected: (value) {
                  showApplied = value;
                  refresh();
                },
                // Elegido lleva la marca (no sólo el color) en vez del icono.
                avatar: showApplied
                    ? null
                    : const Icon(Icons.history, size: 18),
                label: const Text('Mostrar planes aplicados'),
              ),
            ),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              RdmAEmpty(
                icon: Icons.event_note_outlined,
                message: showApplied
                    ? 'No hay planes registrados.'
                    : 'No hay planes pendientes.',
              )
            else
              for (final entry in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PlanCard(
                    key: Key('plan-${entry.key}'),
                    rows: entry.value,
                    onApply: () => applyPlan(entry.key),
                  ),
                ),
          ],
        );
      },
    ),
  );
}

/// Un plan: chaco y responsable, campaña, productos y si está pendiente o
/// aplicado. Se despliega para ver cada producto con su dosis y cantidad y,
/// si sigue pendiente, «Aplicar este plan».
class _PlanCard extends StatelessWidget {
  const _PlanCard({super.key, required this.rows, required this.onApply});

  final List<Map<String, Object?>> rows;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final first = rows.first;
    final applied = first['plan_status'] == 'APPLIED';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Sin las líneas que ExpansionTile dibuja al abrirse.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
          iconColor: AgroColors.ink,
          collapsedIconColor: AgroColors.muted,
          title: Text(
            '${first['farm_name']} · ${first['owner_name']}',
            style: AgroText.value,
          ),
          // El estado va en palabras y en la etiqueta; el indicador de
          // expansión queda libre (UIBUG-046).
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${first['campaign_name']} · ${rdmAProducts(rows.length)}',
                  style: AgroText.detail,
                ),
                const SizedBox(height: 6),
                // Un plan consumido se marca en la propia fila: no hace falta
                // desplegarla para saber que ya no está en juego.
                StatusBadge(
                  label: applied ? 'Aplicado' : 'Pendiente',
                  tone: applied ? BadgeTone.neutral : BadgeTone.ok,
                ),
              ],
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: AmountAside(
                  amount: formatQuantity(
                    row['required_quantity_base'] as int,
                    row['unit'] as String,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row['product_name'] as String,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AgroColors.ink,
                        ),
                      ),
                      Text(
                        'Área ${formatHectares(row['area_m2'] as int)} · '
                        'dosis ${formatQuantity(row['dose_base_per_ha'] as int, row['unit'] as String)}/ha',
                        style: AgroText.detail,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // Un plan aplicado no ofrece la acción: no es que se intente y
            // falle, es que ya no procede (UIBUG-045). El repositorio la
            // rechaza además por su cuenta.
            if (applied)
              const Text(
                'Ya aplicado. Para repetir la aplicación, cree un plan nuevo.',
                style: AgroText.detail,
              )
            else
              // Al volver del formulario hay que recargar: el plan acaba de
              // consumirse y una lista sin refrescar seguiría ofreciendo
              // «Aplicar» sobre algo ya aplicado.
              PrimaryActionButton(
                label: 'Aplicar este plan',
                icon: Icons.spa_outlined,
                iconFirst: true,
                onPressed: onApply,
              ),
          ],
        ),
      ),
    );
  }
}
