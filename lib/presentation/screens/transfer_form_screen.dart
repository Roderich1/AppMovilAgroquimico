import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/operation_mode.dart';
import '../../domain/person_roles.dart';
import '../../operation_mode_controller.dart';
import '../theme/agro_theme.dart';
import '../widgets/adaptive_entity_picker.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/mode_notice.dart';

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
    // Origen y destino posibles según rol privado, titular y modalidad: el
    // titular registrado como administrador de pagos también transfiere.
    peopleFuture = ref
        .read(repositoryProvider)
        .peopleFor(PersonPurpose.transferParty);
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
    // OE3 (2026-11-03): una cantidad con formato rechazado («1.5», «1,500»)
    // no es «ninguna cantidad»: se dice cuál y por qué, con el mensaje de la
    // regla única (docs/44_NUMERIC_INPUT_SPEC.md §6). La regla no cambia.
    for (final row in available) {
      final parsed = parseNumericInput(quantities[row['product_id']]!.text);
      if (parsed.status == NumericInputStatus.ambiguous ||
          parsed.status == NumericInputStatus.malformed) {
        showError(
          context,
          'Revise la cantidad de ${row['product_name']}. ${parsed.message}',
        );
        return;
      }
    }
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
            // Con muchas líneas el contenido se desplaza en vez de recortarse.
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('De: $from\nA: $to'),
                const Divider(),
                // D-07 (RN-35, decisión del autor del 2026-10-27): antes de
                // confirmar se dice que la entrega no genera deuda, sea el
                // destino un familiar o un tercero que paga por compra. Va
                // justo después de De/A para que se lea antes de la lista,
                // por larga que sea.
                Text(
                  transferNoDebtNotice('$to'),
                  key: const Key('transfer-no-debt-notice'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Esta transferencia no registra ningún cargo ni cobro a '
                  '$to. El costo del producto entregado sólo es de '
                  'referencia, no un precio de venta.',
                ),
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
  Widget build(BuildContext context) =>
      ref.watch(operationModeProvider) == OperationMode.personal
      ? Scaffold(
          appBar: AppBar(title: const Text('Nueva transferencia')),
          body: SharedOnlyNotice(onBack: () => context.go('/operaciones')),
        )
      : _form(context);

  Widget _form(BuildContext context) => PopScope(
    canPop: !dirty && !saving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !saving) requestClose();
    },
    child: Scaffold(
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: AgroColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: FutureBuilder<List<Map<String, Object?>>>(
            future: peopleFuture,
            builder: (context, snapshot) => FilledButton.icon(
              onPressed: saving || !snapshot.hasData
                  ? null
                  : () => submit(snapshot.data!),
              style: FilledButton.styleFrom(
                backgroundColor: AgroColors.ink,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 56),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.check, color: AgroColors.lime),
              label: const Text(
                'Revisar y confirmar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Map<String, Object?>>>(
          future: peopleFuture,
          builder: (context, snapshot) {
            final header = FlowTopBar(
              onBack: saving ? null : requestClose,
              label: 'Nueva transferencia',
              trailing: saving
                  ? const SizedBox.square(
                      dimension: 44,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            );
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  header,
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
            final people = snapshot.data!;
            final origin = people.where((p) => p['id'] == fromId).firstOrNull;
            final destination = people
                .where((p) => p['id'] == toId)
                .firstOrNull;
            final query = search.text.trim().toLowerCase();
            final visible = available
                .where((r) => matchesSearch(r['product_name'] as String, query))
                .toList();
            final originName = origin?['name'] as String?;
            // Todo el formulario construido (no ListView): con muchas líneas
            // los selectores de arriba siguen existiendo al teclear abajo.
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 12),
                  const Text('¿Quién entrega a quién?', style: AgroText.h1),
                  const SizedBox(height: 12),
                  AgroGroup(
                    children: [
                      AdaptiveEntityPicker<Map<String, Object?>>(
                        label: 'Persona origen',
                        rowStyle: true,
                        items: people,
                        value: origin,
                        labelOf: (p) => p['name'] as String,
                        // Mismo criterio de subtítulo que el selector de
                        // destino y que el del formulario de compra
                        // (UIBUG-054/016).
                        secondaryOf: (p) => personRoleLabel(p['role']),
                        onChanged: selectOrigin,
                      ),
                      AdaptiveEntityPicker<Map<String, Object?>>(
                        label: 'Persona destino',
                        rowStyle: true,
                        items: people.where((p) => p['id'] != fromId).toList(),
                        value: destination,
                        labelOf: (p) => p['name'] as String,
                        secondaryOf: (p) => personRoleLabel(p['role']),
                        onChanged: (p) => setState(() {
                          toId = p?['id'] as int?;
                          dirty = true;
                        }),
                        enabled: fromId != null,
                        placeholder: fromId == null
                            ? 'Elija primero quién entrega'
                            : 'Elegir',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // D-07: una entrega no es una venta ni un préstamo.
                  const NoticeBox(
                    icon: Icons.info_outline,
                    text:
                        'Una transferencia no genera deuda entre las personas.',
                  ),
                  const SizedBox(height: 20),
                  // Antes de elegir origen la sección mostraba un `0` a secas,
                  // que se leía como un dato real (UIBUG-060): el recuento sólo
                  // aparece con un origen del que contar.
                  SectionHeader(
                    title: '¿Qué entrega?',
                    trailing: fromId == null ? null : '${available.length}',
                  ),
                  const SizedBox(height: 8),
                  // Estado vacío explícito: dice qué falta hacer.
                  if (fromId == null)
                    const EmptyState(
                      icon: Icons.person_search_outlined,
                      message: 'Seleccione un origen para ver su inventario.',
                    ),
                  if (fromId != null && available.length >= 8) ...[
                    TextField(
                      controller: search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Buscar producto',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (loadingProducts) const LinearProgressIndicator(),
                  if (!loadingProducts && fromId != null && available.isEmpty)
                    const EmptyState(
                      icon: Icons.inventory_2_outlined,
                      message: 'Esta persona no tiene stock disponible.',
                    ),
                  if (available.isNotEmpty)
                    // Sin cota de altura: la lista crece con su contenido y el
                    // desplazamiento es el del formulario (UIBUG-055).
                    AgroGroup(
                      children: [
                        for (final row in visible)
                          _ProductLine(
                            row: row,
                            owner: originName,
                            controller: quantities[row['product_id'] as int],
                            onChanged: () => setState(() => dirty = true),
                          ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// Un producto del origen con su cantidad a entregar: cuánto tiene la
/// persona, en cuántos lotes y el costo de referencia del siguiente lote
/// (FIFO), que no es un precio.
class _ProductLine extends StatelessWidget {
  const _ProductLine({
    required this.row,
    required this.owner,
    required this.controller,
    required this.onChanged,
  });

  final Map<String, Object?> row;
  final String? owner;
  final TextEditingController? controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final unit = row['unit'] as String;
    final stock = formatQuantity(row['available_base'] as int, unit);
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      title: Text(
        row['product_name'] as String,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AgroColors.ink,
        ),
      ),
      subtitle: Text(
        '${owner == null ? stock : '$owner tiene $stock'} disponibles · '
        '${row['lot_count']} lote(s) · costo de referencia '
        '${formatBob(row['next_fifo_cost_minor'] as int)}/$unit',
        style: AgroText.detail,
      ),
      trailing: SizedBox(
        width: 105,
        child: TextField(
          controller: controller,
          onChanged: (_) => onChanged(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AgroText.value,
          decoration: InputDecoration(
            labelText: unit,
            // El `0` es una pista, no texto que haya que borrar antes de
            // escribir (UIBUG-034).
            hintText: '0',
            isDense: true,
          ),
        ),
      ),
    );
  }
}
