import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/agro_repository.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../widgets/adaptive_entity_picker.dart';
import '../widgets/common.dart';

typedef _ApplicationCatalogs = ({
  List<Map<String, Object?>> people,
  List<Map<String, Object?>> farms,
  Map<String, Object?> campaign,
});

class ApplicationFormScreen extends ConsumerStatefulWidget {
  const ApplicationFormScreen({super.key, this.planId});
  final int? planId;
  @override
  ConsumerState<ApplicationFormScreen> createState() =>
      _ApplicationFormScreenState();
}

class _ApplicationFormScreenState extends ConsumerState<ApplicationFormScreen> {
  late Future<_ApplicationCatalogs> catalogs;
  int? personId, farmId;
  List<Map<String, Object?>> stocks = [];
  final lines = <_ApplicationLineEditor>[];
  final area = TextEditingController();
  final notes = TextEditingController();
  Map<String, Object?>? productToAdd;
  bool dirty = false, saving = false, loadingStock = false;

  @override
  void initState() {
    super.initState();
    catalogs = _load();
  }

  Future<_ApplicationCatalogs> _load() async {
    final repo = ref.read(repositoryProvider);
    final active = await repo.activeCampaign();
    if (active == null)
      throw BusinessRuleException(
        'Active una campaña antes de registrar aplicaciones.',
      );
    final result = (
      people: (await repo.people()).where((p) => p['role'] != 'ADMIN').toList(),
      farms: await repo.farms(),
      campaign: active,
    );
    if (widget.planId != null) {
      final plan = await repo.planForApplication(widget.planId!);
      if (plan.isEmpty) throw BusinessRuleException('El plan no existe.');
      if (plan.first['campaign_id'] != active['id']) {
        throw BusinessRuleException(
          'El plan no pertenece a la campaña activa.',
        );
      }
      personId = plan.first['person_id'] as int;
      farmId = plan.first['farm_id'] as int;
      area.text = ((plan.first['area_m2'] as int) / 10000).toString();
      stocks = await repo.availableProductsForOwner(personId!);
      for (final item in plan) {
        final stock =
            stocks
                .where((row) => row['product_id'] == item['product_id'])
                .firstOrNull ??
            <String, Object?>{
              'product_id': item['product_id'],
              'product_name': item['product_name'],
              'unit': item['unit'],
              'available_base': 0,
              'lot_count': 0,
              'next_fifo_cost_minor': 0,
            };
        final line = _ApplicationLineEditor(stock);
        line.dose.text = ((item['dose_base_per_ha'] as int) / 1000).toString();
        line.real.text = ((item['required_quantity_base'] as int) / 1000)
            .toString();
        lines.add(line);
        line.cost = await repo.estimateFifoCost(
          personId: personId!,
          productId: item['product_id'] as int,
          quantityBase: item['required_quantity_base'] as int,
        );
      }
    }
    return result;
  }

  @override
  void dispose() {
    area.dispose();
    notes.dispose();
    for (final line in lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> selectPerson(Map<String, Object?>? person) async {
    final id = person?['id'] as int?;
    setState(() {
      personId = id;
      // Al cambiar de persona el chaco deja de ser válido, porque la lista de
      // chacos se filtra por propietario. Si se limpia la persona (id nulo) se
      // conserva la selección previa, que es el comportamiento existente.
      if (id != null) farmId = null;
      loadingStock = id != null;
      stocks = [];
      dirty = true;
    });
    _clearLines();
    if (id == null) return;
    final result = await ref
        .read(repositoryProvider)
        .availableProductsForOwner(id);
    if (!mounted || personId != id) return;
    setState(() {
      stocks = result;
      loadingStock = false;
    });
  }

  void _clearLines() {
    for (final line in lines) {
      line.dispose();
    }
    lines.clear();
    productToAdd = null;
  }

  Future<void> selectFarm(Map<String, Object?>? farm) async {
    if (farm == null) {
      setState(() {
        farmId = null;
        dirty = true;
      });
      return;
    }
    final owner = farm['owner_person_id'] as int;
    final hectares = (farm['area_m2'] as int) / 10000;
    area.text = hectares.toStringAsFixed(
      hectares == hectares.truncateToDouble() ? 0 : 2,
    );
    if (personId != owner) {
      final catalogsValue = _latestCatalogs;
      if (catalogsValue != null) {
        await selectPerson(
          catalogsValue.people.firstWhere((p) => p['id'] == owner),
        );
      }
    }
    if (mounted)
      setState(() {
        farmId = farm['id'] as int;
        dirty = true;
      });
  }

  _ApplicationCatalogs? _latestCatalogs;

  void addProduct() {
    final product = productToAdd;
    if (product == null) return;
    if (lines.any(
      (line) => line.product['product_id'] == product['product_id'],
    )) {
      showError(context, 'El producto ya está agregado.');
      return;
    }
    final line = _ApplicationLineEditor(product);
    lines.add(line);
    productToAdd = null;
    setState(() => dirty = true);
  }

  Future<void> estimate(_ApplicationLineEditor line) async {
    final q = tryParseBase(line.real.text) ?? 0;
    if (personId == null || q <= 0) {
      if (mounted) setState(() => line.cost = 0);
      return;
    }
    final cost = await ref
        .read(repositoryProvider)
        .estimateFifoCost(
          personId: personId!,
          productId: line.product['product_id'] as int,
          quantityBase: q,
        );
    if (mounted && q == (tryParseBase(line.real.text) ?? 0))
      setState(() => line.cost = cost);
  }

  int theoretical(_ApplicationLineEditor line) =>
      ((tryParseDecimal(area.text) ?? 0) *
              (tryParseDecimal(line.dose.text) ?? 0) *
              1000)
          .round();

  Future<bool> confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Descartar cambios?'),
          content: const Text('La aplicación todavía no fue guardada.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Descartar'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> requestClose() async {
    if (!dirty || await confirmDiscard()) {
      if (mounted) {
        setState(() => dirty = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    }
  }

  Future<void> submit(_ApplicationCatalogs data) async {
    if (personId == null || farmId == null || lines.isEmpty) {
      showError(context, 'Seleccione persona, chaco y al menos un producto.');
      return;
    }
    final drafts = <ApplicationLineDraft>[];
    for (final line in lines) {
      final real = tryParseBase(line.real.text) ?? 0;
      final stock = line.product['available_base'] as int;
      if (real <= 0 || real > stock) {
        showError(
          context,
          'Revise las cantidades: todos los productos deben tener stock suficiente.',
        );
        return;
      }
      drafts.add(
        ApplicationLineDraft(
          productId: line.product['product_id'] as int,
          quantityBase: real,
          treatedAreaM2: ((tryParseDecimal(area.text) ?? 0) * 10000).round(),
          doseBasePerHa: tryParseBase(line.dose.text),
          theoreticalQuantityBase: theoretical(line),
        ),
      );
    }
    setState(() => saving = true);
    try {
      await ref
          .read(repositoryProvider)
          .confirmApplication(
            ApplicationDraft(
              personId: personId!,
              farmId: farmId!,
              campaignId: data.campaign['id'] as int,
              appliedAt: DateTime.now(),
              notes: notes.text.trim(),
              treatedAreaM2: ((tryParseDecimal(area.text) ?? 0) * 10000)
                  .round(),
              planId: widget.planId,
              lines: drafts,
            ),
          );
      if (!mounted) return;
      setState(() {
        dirty = false;
        saving = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
    } catch (error) {
      if (mounted) {
        setState(() => saving = false);
        showError(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty && !saving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !saving) requestClose();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Nueva aplicación'),
        leading: IconButton(
          onPressed: saving ? null : requestClose,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FutureBuilder<_ApplicationCatalogs>(
            future: catalogs,
            builder: (context, snapshot) => FilledButton.icon(
              onPressed: saving || !snapshot.hasData
                  ? null
                  : () => submit(snapshot.data!),
              icon: const Icon(Icons.check),
              label: Text(saving ? 'Guardando…' : 'Confirmar aplicación'),
            ),
          ),
        ),
      ),
      body: FutureBuilder<_ApplicationCatalogs>(
        future: catalogs,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(snapshot.error!),
            );
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          _latestCatalogs = data;
          final person = data.people
              .where((p) => p['id'] == personId)
              .firstOrNull;
          final farms = data.farms
              .where(
                (f) => personId == null || f['owner_person_id'] == personId,
              )
              .toList();
          final farm = data.farms.where((f) => f['id'] == farmId).firstOrNull;
          final addable = stocks
              .where(
                (p) => !lines.any(
                  (line) => line.product['product_id'] == p['product_id'],
                ),
              )
              .toList();
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Campaña activa · ${data.campaign['name']}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 600;
                    final fields = [
                      AdaptiveEntityPicker<Map<String, Object?>>(
                        label: 'Persona',
                        items: data.people,
                        value: person,
                        labelOf: (p) => p['name'] as String,
                        onChanged: selectPerson,
                      ),
                      AdaptiveEntityPicker<Map<String, Object?>>(
                        label: 'Chaco',
                        items: farms,
                        value: farm,
                        labelOf: (f) => f['name'] as String,
                        secondaryOf: (f) =>
                            '${(f['area_m2'] as int) / 10000} ha',
                        onChanged: selectFarm,
                        enabled: personId != null,
                      ),
                    ];
                    return wide
                        ? Row(
                            children: [
                              Expanded(child: fields[0]),
                              const SizedBox(width: 12),
                              Expanded(child: fields[1]),
                            ],
                          )
                        : Column(
                            children: [
                              fields[0],
                              const SizedBox(height: 12),
                              fields[1],
                            ],
                          );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: area,
                  onChanged: (_) {
                    setState(() => dirty = true);
                    for (final line in lines) {
                      estimate(line);
                    }
                  },
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Área tratada (ha)',
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
                    if (loadingStock)
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AdaptiveEntityPicker<Map<String, Object?>>(
                        label: 'Agregar producto',
                        items: addable,
                        value: productToAdd,
                        labelOf: (p) => p['product_name'] as String,
                        secondaryOf: (p) =>
                            '${formatQuantity(p['available_base'] as int, p['unit'] as String)} · FIFO ${formatBob(p['next_fifo_cost_minor'] as int)}/${p['unit']}',
                        onChanged: (p) => setState(() => productToAdd = p),
                        enabled: personId != null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: productToAdd == null ? null : addProduct,
                      tooltip: 'Agregar producto',
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (lines.isEmpty)
                  const EmptyState(
                    icon: Icons.science_outlined,
                    message: 'Agregue los productos de la mezcla.',
                  ),
                for (final line in lines)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      key: ValueKey(line.product['product_id']),
                      title: Text(
                        line.product['product_name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${formatQuantity(tryParseBase(line.real.text) ?? 0, line.unit)} real / ${formatQuantity(theoretical(line), line.unit)} teórico · ${formatBob(line.cost)}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Quitar',
                        onPressed: () {
                          setState(() {
                            lines.remove(line);
                            line.dispose();
                            dirty = true;
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Column(
                            children: [
                              Text(
                                'Disponible ${formatQuantity(line.product['available_base'] as int, line.unit)} · stock después ${formatQuantity((line.product['available_base'] as int) - (tryParseBase(line.real.text) ?? 0), line.unit)}',
                              ),
                              const SizedBox(height: 8),
                              LayoutBuilder(
                                builder: (context, c) {
                                  final fields = [
                                    TextField(
                                      controller: line.dose,
                                      onChanged: (_) {
                                        setState(() => dirty = true);
                                      },
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: InputDecoration(
                                        labelText: 'Dosis (${line.unit}/ha)',
                                      ),
                                    ),
                                    TextField(
                                      controller: line.real,
                                      onChanged: (_) {
                                        setState(() => dirty = true);
                                        estimate(line);
                                      },
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: InputDecoration(
                                        labelText:
                                            'Cantidad real (${line.unit})',
                                      ),
                                    ),
                                  ];
                                  return c.maxWidth >= 520
                                      ? Row(
                                          children: [
                                            Expanded(child: fields[0]),
                                            const SizedBox(width: 8),
                                            Expanded(child: fields[1]),
                                          ],
                                        )
                                      : Column(
                                          children: [
                                            fields[0],
                                            const SizedBox(height: 8),
                                            fields[1],
                                          ],
                                        );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  onChanged: (_) => dirty = true,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notas'),
                ),
                const SizedBox(height: 100),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _ApplicationLineEditor {
  _ApplicationLineEditor(this.product);
  final Map<String, Object?> product;
  final dose = TextEditingController();
  final real = TextEditingController();
  int cost = 0;
  String get unit => product['unit'] as String;
  void dispose() {
    dose.dispose();
    real.dispose();
  }
}
