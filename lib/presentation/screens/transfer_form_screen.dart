import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../widgets/adaptive_entity_picker.dart';
import '../widgets/common.dart';

class TransferFormScreen extends ConsumerStatefulWidget {
  const TransferFormScreen({super.key});
  @override
  ConsumerState<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends ConsumerState<TransferFormScreen> {
  late Future<List<Map<String, Object?>>> peopleFuture;
  int? fromId, toId;
  List<Map<String, Object?>> available = [];
  final quantities = <int, TextEditingController>{};
  final search = TextEditingController();
  bool loadingProducts = false, saving = false, dirty = false;

  @override
  void initState() {
    super.initState();
    peopleFuture = ref.read(repositoryProvider).people();
  }

  @override
  void dispose() {
    search.dispose();
    for (final c in quantities.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> selectOrigin(Map<String, Object?>? person) async {
    final id = person?['id'] as int?;
    setState(() {
      fromId = id;
      if (toId == id) toId = null;
      loadingProducts = id != null;
      dirty = true;
      available = [];
    });
    for (final c in quantities.values) {
      c.dispose();
    }
    quantities.clear();
    if (id == null) return;
    final rows = await ref
        .read(repositoryProvider)
        .availableProductsForOwner(id);
    if (!mounted || fromId != id) return;
    for (final row in rows) {
      // Campo vacio con `0` como pista: precargar el texto "0" obligaba a
      // borrarlo y escribir `5` dejaba `05` (UIBUG-034).
      quantities[row['product_id'] as int] = TextEditingController();
    }
    setState(() {
      available = rows;
      loadingProducts = false;
    });
  }

  List<TransferItemDraft> get selectedItems => [
    for (final row in available)
      if ((tryParseBase(quantities[row['product_id']]!.text) ?? 0) > 0)
        TransferItemDraft(
          productId: row['product_id'] as int,
          quantityBase: tryParseBase(quantities[row['product_id']]!.text)!,
        ),
  ];

  Future<bool> confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Descartar cambios?'),
          content: const Text('La transferencia todavía no fue guardada.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              // Criterio unico de accion destructiva, el mismo que usa
              // `confirmDestructiveAction` en las reversiones (UIBUG-033).
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Descartar cambios'),
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

  Future<void> submit(List<Map<String, Object?>> people) async {
    final items = selectedItems;
    if (fromId == null || toId == null || fromId == toId || items.isEmpty) {
      showError(
        context,
        'Seleccione origen, destino y al menos una cantidad válida.',
      );
      return;
    }
    for (final item in items) {
      final stock =
          available.firstWhere(
                (row) => row['product_id'] == item.productId,
              )['available_base']
              as int;
      if (item.quantityBase > stock) {
        showError(context, 'Una cantidad supera el stock disponible.');
        return;
      }
    }
    final from = people.firstWhere((p) => p['id'] == fromId)['name'];
    final to = people.firstWhere((p) => p['id'] == toId)['name'];
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Confirmar transferencia'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('De: $from\nA: $to'),
                const Divider(),
                for (final item in items)
                  Text(
                    '${available.firstWhere((r) => r['product_id'] == item.productId)['product_name']}: ${formatQuantity(item.quantityBase, available.firstWhere((r) => r['product_id'] == item.productId)['unit'] as String)}',
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Revisar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => saving = true);
    try {
      await ref
          .read(repositoryProvider)
          .transferProductsFifo(
            fromPersonId: fromId!,
            toPersonId: toId!,
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
        title: const Text('Nueva transferencia'),
        leading: IconButton(
          onPressed: saving ? null : requestClose,
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          if (saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: peopleFuture,
            builder: (context, snapshot) => FilledButton.icon(
              onPressed: saving || !snapshot.hasData
                  ? null
                  : () => submit(snapshot.data!),
              icon: const Icon(Icons.check),
              label: const Text('Revisar y confirmar'),
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: peopleFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return EmptyState(
              icon: Icons.error_outline,
              message: friendlyError(snapshot.error!),
            );
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          final people = snapshot.data!
              .where((p) => p['role'] != 'ADMIN')
              .toList();
          final origin = people.where((p) => p['id'] == fromId).firstOrNull;
          final destination = people.where((p) => p['id'] == toId).firstOrNull;
          final query = search.text.trim().toLowerCase();
          final visible = available
              .where((r) => matchesSearch(r['product_name'] as String, query))
              .toList();
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  '1. Origen',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                AdaptiveEntityPicker<Map<String, Object?>>(
                  label: 'Persona origen',
                  items: people,
                  value: origin,
                  labelOf: (p) => p['name'] as String,
                  // Mismo criterio de subtítulo que el selector de destino y
                  // que el del formulario de compra (UIBUG-054/016).
                  secondaryOf: (p) => personRoleLabel(p['role']),
                  onChanged: selectOrigin,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '2. Productos disponibles',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    // Antes de elegir origen la sección mostraba un `0` a
                    // secas, que se leía como un dato real ("esta persona
                    // tiene 0") cuando en realidad todavía no se había
                    // preguntado por nadie (UIBUG-060). El recuento sólo
                    // aparece cuando hay un origen del que contar.
                    if (fromId != null) Text('${available.length}'),
                  ],
                ),
                const SizedBox(height: 8),
                // Estado vacío explícito: dice qué falta hacer en vez de
                // dejar la sección en blanco tras el encabezado.
                if (fromId == null)
                  const EmptyState(
                    icon: Icons.person_search_outlined,
                    message: 'Seleccione un origen para ver su inventario.',
                  ),
                if (fromId != null && available.length >= 8)
                  TextField(
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Buscar producto',
                      isDense: true,
                    ),
                  ),
                if (loadingProducts) const LinearProgressIndicator(),
                if (!loadingProducts && fromId != null && available.isEmpty)
                  const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: 'Esta persona no tiene stock disponible.',
                  ),
                if (available.isNotEmpty)
                  // Sin cota de altura: la lista crece con su contenido y el
                  // desplazamiento es el del formulario, de modo que ninguna
                  // fila queda seccionada sin señal de continuidad
                  // (UIBUG-055).
                  Card(
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final row = visible[index];
                        final id = row['product_id'] as int;
                        final unit = row['unit'] as String;
                        return ListTile(
                          title: Text(
                            row['product_name'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${formatQuantity(row['available_base'] as int, unit)} disponibles · ${row['lot_count']} lote(s) · próximo FIFO ${formatBob(row['next_fifo_cost_minor'] as int)}/$unit',
                          ),
                          trailing: SizedBox(
                            width: 105,
                            child: TextField(
                              controller: quantities[id],
                              onChanged: (_) => setState(() => dirty = true),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: unit,
                                // El `0` es una pista, no texto que haya que
                                // borrar antes de escribir (UIBUG-034).
                                hintText: '0',
                                isDense: true,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  '3. Destino',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                AdaptiveEntityPicker<Map<String, Object?>>(
                  label: 'Persona destino',
                  items: people.where((p) => p['id'] != fromId).toList(),
                  value: destination,
                  labelOf: (p) => p['name'] as String,
                  secondaryOf: (p) => personRoleLabel(p['role']),
                  onChanged: (p) => setState(() {
                    toId = p?['id'] as int?;
                    dirty = true;
                  }),
                  enabled: fromId != null,
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
