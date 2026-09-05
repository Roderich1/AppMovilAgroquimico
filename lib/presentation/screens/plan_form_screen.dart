import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/agro_repository.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../widgets/adaptive_entity_picker.dart';
import '../widgets/common.dart';

typedef _PlanCatalogs = ({
  Map<String, Object?> campaign,
  List<Map<String, Object?>> farms,
  List<Map<String, Object?>> products,
});

class PlanFormScreen extends ConsumerStatefulWidget {
  const PlanFormScreen({super.key});
  @override
  ConsumerState<PlanFormScreen> createState() => _PlanFormScreenState();
}

class _PlanFormScreenState extends ConsumerState<PlanFormScreen> {
  late Future<_PlanCatalogs> future;
  int? farmId;
  Map<String, Object?>? productToAdd;
  final area = TextEditingController();
  final lines = <_PlanLine>[];
  Map<int, int> ownerStock = {};
  bool dirty = false, saving = false;
  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<_PlanCatalogs> _load() async {
    final r = ref.read(repositoryProvider);
    final active = await r.activeCampaign();
    if (active == null)
      throw BusinessRuleException('Active una campaña antes de planificar.');
    return (
      campaign: active,
      farms: await r.farms(),
      products: await r.products(),
    );
  }

  @override
  void dispose() {
    area.dispose();
    for (final l in lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> selectFarm(Map<String, Object?>? farm) async {
    setState(() {
      farmId = farm?['id'] as int?;
      dirty = true;
      ownerStock = {};
    });
    if (farm == null) return;
    final hectares = (farm['area_m2'] as int) / 10000;
    // Convenio es-BO: el campo debe precargarse como el usuario podria
    // teclearlo (coma decimal), no como "80.0" (UIBUG-003).
    area.text = formatForInput(hectares, maxDecimals: 2);
    final rows = await ref
        .read(repositoryProvider)
        .personStockSummary(farm['owner_person_id'] as int);
    if (!mounted || farmId != farm['id']) return;
    setState(
      () => ownerStock = {
        for (final r in rows)
          r['product_id'] as int: r['available_base'] as int,
      },
    );
  }

  void add() {
    final p = productToAdd;
    if (p == null) return;
    if (lines.any((l) => l.product['id'] == p['id'])) {
      showError(context, 'El producto ya está agregado.');
      return;
    }
    setState(() {
      lines.add(_PlanLine(p));
      productToAdd = null;
      dirty = true;
    });
  }

  int needed(_PlanLine l) =>
      ((tryParseDecimal(area.text) ?? 0) *
              (tryParseDecimal(l.dose.text) ?? 0) *
              1000)
          .round();
  Future<bool> discard() async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('¿Descartar cambios?'),
          content: const Text('El plan todavía no fue guardado.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              // Criterio unico de accion destructiva, el mismo que usa
              // `confirmDestructiveAction` en las reversiones (UIBUG-033).
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Descartar cambios'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> close() async {
    if (!dirty || await discard()) {
      if (mounted) {
        setState(() => dirty = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    }
  }

  Future<void> submit(_PlanCatalogs data) async {
    // El mensaje unico mencionaba el chaco aunque ya estuviera elegido
    // (UIBUG-032): ahora dice exactamente que falta.
    if (farmId == null && lines.isEmpty) {
      showError(context, 'Seleccione el chaco y agregue al menos un producto.');
      return;
    }
    if (farmId == null) {
      showError(context, 'Seleccione el chaco.');
      return;
    }
    if (lines.isEmpty) {
      showError(context, 'Agregue al menos un producto al plan.');
      return;
    }
    final items = <PlanItemDraft>[];
    for (final l in lines) {
      final d = tryParseBase(l.dose.text) ?? 0;
      if (d <= 0) {
        showError(context, 'Todas las dosis deben ser mayores a cero.');
        return;
      }
      items.add(
        PlanItemDraft(productId: l.product['id'] as int, doseBasePerHa: d),
      );
    }
    setState(() => saving = true);
    try {
      await ref
          .read(repositoryProvider)
          .addPlanMulti(
            farmId: farmId!,
            campaignId: data.campaign['id'] as int,
            areaM2: ((tryParseDecimal(area.text) ?? 0) * 10000).round(),
            items: items,
          );
      if (!mounted) return;
      setState(() {
        dirty = false;
        saving = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty && !saving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !saving) close();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Nueva planificación'),
        leading: IconButton(
          onPressed: saving ? null : close,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FutureBuilder<_PlanCatalogs>(
            future: future,
            builder: (context, s) => FilledButton.icon(
              onPressed: saving || !s.hasData ? null : () => submit(s.data!),
              icon: const Icon(Icons.check),
              label: const Text('Guardar planificación'),
            ),
          ),
        ),
      ),
      body: FutureBuilder<_PlanCatalogs>(
        future: future,
        builder: (context, s) {
          if (s.hasError)
            return EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(s.error!),
            );
          if (!s.hasData)
            return const Center(child: CircularProgressIndicator());
          final d = s.data!;
          final farm = d.farms.where((f) => f['id'] == farmId).firstOrNull;
          final addable = d.products
              .where((p) => !lines.any((l) => l.product['id'] == p['id']))
              .toList();
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Campaña activa · ${d.campaign['name']}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 16),
                AdaptiveEntityPicker<Map<String, Object?>>(
                  label: 'Chaco',
                  items: d.farms,
                  value: farm,
                  labelOf: (f) => f['name'] as String,
                  secondaryOf: (f) =>
                      '${f['owner_name']} · ${formatHectares(f['area_m2'] as int)}',
                  onChanged: selectFarm,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: area,
                  onChanged: (_) => setState(() => dirty = true),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Área planificada (ha)',
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Productos (${lines.length})',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton.filled(
                      onPressed: productToAdd == null ? null : add,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                AdaptiveEntityPicker<Map<String, Object?>>(
                  label: 'Agregar producto',
                  items: addable,
                  value: productToAdd,
                  labelOf: (p) => p['name'] as String,
                  secondaryOf: (p) => p['unit'] as String,
                  onChanged: (p) => setState(() => productToAdd = p),
                  enabled: farmId != null,
                ),
                const SizedBox(height: 8),
                if (lines.isEmpty)
                  const EmptyState(
                    icon: Icons.event_note_outlined,
                    message: 'Agregue los productos de la planificación.',
                  ),
                for (final l in lines)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                        l.product['name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          TextField(
                            controller: l.dose,
                            onChanged: (_) => setState(() => dirty = true),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Dosis (${l.product['unit']}/ha)',
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Builder(
                            builder: (_) {
                              final need = needed(l);
                              final stock = ownerStock[l.product['id']] ?? 0;
                              final missing = need > stock ? need - stock : 0;
                              return Text(
                                'Necesita ${formatQuantity(need, l.product['unit'] as String)} · stock ${formatQuantity(stock, l.product['unit'] as String)} · ${missing == 0 ? 'cubierto' : 'comprar ${formatQuantity(missing, l.product['unit'] as String)}'}',
                              );
                            },
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        onPressed: () {
                          setState(() {
                            lines.remove(l);
                            l.dispose();
                            dirty = true;
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _PlanLine {
  _PlanLine(this.product);
  final Map<String, Object?> product;
  final dose = TextEditingController();
  void dispose() => dose.dispose();
}
