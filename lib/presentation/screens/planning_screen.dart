import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';

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
  Widget build(BuildContext context) => PageFrame(
    title: 'Planificación',
    subtitle: 'Necesidad, cobertura y compra por mezcla de productos.',
    action: FilledButton.icon(
      onPressed: add,
      icon: const Icon(Icons.add),
      label: const Text('Nuevo plan'),
    ),
    child: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, s) {
        if (s.hasError)
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(s.error!),
          );
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
          children: [
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
                avatar: const Icon(Icons.history, size: 18),
                label: const Text('Mostrar planes aplicados'),
              ),
            ),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              EmptyState(
                icon: Icons.event_note_outlined,
                message: showApplied
                    ? 'No hay planes registrados.'
                    : 'No hay planes pendientes.',
              )
            else
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final rows = visible[index].value;
                    final first = rows.first;
                    final applied = first['plan_status'] == 'APPLIED';
                    return ExpansionTile(
                      title: Text(
                        '${first['farm_name']} · ${first['owner_name']}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${first['campaign_name']} · ${rows.length} producto(s) · '
                        '${applied ? 'aplicado' : 'pendiente'}',
                      ),
                      // Un plan consumido se marca en la propia fila: no hace
                      // falta desplegarla para saber que ya no está en juego.
                      trailing: applied
                          ? const Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text('Aplicado'),
                            )
                          : null,
                      // El chevron del `ExpansionTile` estaba ocupado por el
                      // botón "Aplicar", así que nada indicaba que la fila se
                      // desplegara (UIBUG-046). Ahora el botón va dentro y el
                      // indicador de expansión vuelve a verse.
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            // Un plan aplicado no ofrece la acción: no es que
                            // se intente y falle, es que ya no procede
                            // (UIBUG-045). El repositorio la rechaza además
                            // por su cuenta.
                            child: applied
                                ? Text(
                                    'Ya aplicado. Para repetir la aplicación, '
                                    'cree un plan nuevo.',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outline,
                                    ),
                                  )
                                : FilledButton.tonalIcon(
                                    // Al volver del formulario hay que
                                    // recargar: el plan acaba de consumirse y
                                    // una lista sin refrescar seguiría
                                    // ofreciendo "Aplicar" sobre algo ya
                                    // aplicado. El repositorio lo rechazaría,
                                    // pero el usuario vería un error en vez de
                                    // una lista al día.
                                    onPressed: () =>
                                        applyPlan(first['plan_id']! as int),
                                    icon: const Icon(
                                      Icons.agriculture_outlined,
                                    ),
                                    label: const Text('Aplicar este plan'),
                                  ),
                          ),
                        ),
                        for (final row in rows)
                          ListTile(
                            dense: true,
                            title: Text(row['product_name'] as String),
                            subtitle: Text(
                              'Área ${formatHectares(row['area_m2'] as int)} · dosis '
                              '${formatQuantity(row['dose_base_per_ha'] as int, row['unit'] as String)}/ha',
                            ),
                            trailing: Text(
                              formatQuantity(
                                row['required_quantity_base'] as int,
                                row['unit'] as String,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
          ],
        );
      },
    ),
  );
}
