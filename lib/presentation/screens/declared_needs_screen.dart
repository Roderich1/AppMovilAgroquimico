import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/sync/declared_need_store.dart';
import '../../domain/money.dart';
import '../../domain/numeric_input.dart';
import '../../domain/sync/sync_types.dart';
import '../../services/sync/sync_providers.dart';
import '../widgets/common.dart';
import '../widgets/sync_status_banner.dart';

/// Necesidad declarada al sindicato (F06-COLL-04, F06 §3): lo que el
/// agricultor solicita expresamente para una campaña. No nace de planes,
/// stock ni consumo, y no cambia el inventario.
class DeclaredNeedsScreen extends ConsumerStatefulWidget {
  const DeclaredNeedsScreen({super.key});
  @override
  ConsumerState<DeclaredNeedsScreen> createState() =>
      _DeclaredNeedsScreenState();
}

class _DeclaredNeedsScreenState extends ConsumerState<DeclaredNeedsScreen> {
  late Future<List<DeclaredNeed>> needs;

  DeclaredNeedStore get _store => ref.read(declaredNeedStoreProvider);

  @override
  void initState() {
    super.initState();
    needs = _store.needs();
  }

  void _reload() {
    final next = _store.needs();
    setState(() {
      needs = next;
    });
    ref.invalidate(syncSummaryProvider);
  }

  /// Tras encolar: un ciclo del worker (sin acceso verificado no envía). Al
  /// terminar, la lista se relee desde el listener de `build`.
  void _afterEnqueue() {
    _reload();
    unawaited(ref.read(syncControllerProvider.notifier).kick());
  }

  /// C-01: lo que se guardó está en el teléfono; que el sindicato lo acepte
  /// se ve después en la fila. [what] es lo guardado («Guardada»,
  /// «Cambio guardado»…) y [it] el pronombre con que se acepta.
  String _savedMessage(String what, String it) =>
      '$what en el teléfono. Se enviará al sindicato; aquí verá cuándo '
      '$it acepta.';

  /// Misma acción explícita que en Sincronización (C-02): verifica el acceso
  /// si hace falta y lanza un ciclo. No reanuda nada por sí sola.
  Future<void> _syncNow() async {
    await ref.read(syncControllerProvider.notifier).syncNow();
    if (mounted) _reload();
  }

  Future<bool> _confirmDeclaration(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirmar declaración'),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Declarar'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _declare() async {
    final products = await _store.declarableProducts();
    if (!mounted) return;
    if (products.isEmpty) {
      showError(
        context,
        'Vincule primero sus productos con el sindicato para declarar.',
      );
      return;
    }
    final draft = await showDialog<_DeclarationDraft>(
      context: context,
      builder: (_) => _DeclarationDialog(store: _store, products: products),
    );
    if (draft == null || !mounted) return;
    final confirmed = await _confirmDeclaration(
      'Declarar al sindicato: '
      '${formatQuantity(draft.quantityBase, draft.product.baseUnit.majorUnit)} '
      'de ${draft.product.name} para ${draft.campaignName}.',
    );
    if (!confirmed || !mounted) return;
    try {
      await _store.declare(
        referenceDate: draft.date,
        productId: draft.product.productId,
        quantityBase: draft.quantityBase,
      );
      if (mounted) showSuccess(context, _savedMessage('Guardada', 'la'));
      _afterEnqueue();
    } on Object catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _edit(DeclaredNeed need) async {
    final quantity = await showDialog<int>(
      context: context,
      builder: (_) => _QuantityDialog(
        unit: need.baseUnit.majorUnit,
        initialBase: need.quantityBase,
      ),
    );
    if (quantity == null || !mounted) return;
    final confirmed = await _confirmDeclaration(
      'Declarar al sindicato: '
      '${formatQuantity(quantity, need.baseUnit.majorUnit)} de '
      '${need.productName} para ${need.campaignName}. Sustituye el total '
      'anterior; no se suma.',
    );
    if (!confirmed || !mounted) return;
    try {
      await _store.updateQuantity(need.id, quantity);
      if (mounted) {
        showSuccess(context, _savedMessage('Cambio guardado', 'lo'));
      }
      _afterEnqueue();
    } on Object catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _withdraw(DeclaredNeed need) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: 'Anular necesidad',
      detail:
          'Se retira la necesidad de ${need.productName} para '
          '${need.campaignName}. El historial se conserva y la retirada se '
          'enviará al sindicato.',
      confirmLabel: 'Anular',
    );
    if (!confirmed || !mounted) return;
    try {
      await _store.withdraw(need.id);
      if (mounted) {
        showSuccess(context, _savedMessage('Anulación guardada', 'la'));
      }
      _afterEnqueue();
    } on Object catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _history(DeclaredNeed need) async {
    final versions = await _store.history(need.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Historial · ${need.productName}'),
        content: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final version in versions)
                ListTile(
                  title: Text(
                    version.status == DeclaredNeedStatus.active
                        ? formatQuantity(
                            version.quantityBase!,
                            need.baseUnit.majorUnit,
                          )
                        : 'Anulada',
                  ),
                  subtitle: Text(
                    'Versión ${version.version} · ${formatDate(version.createdAt)}',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(DeclaredNeed need) async {
    final operationId = need.syncOperationId;
    if (operationId == null) return;
    try {
      final view = await ref
          .read(syncControllerProvider.notifier)
          .operationView(operationId);
      if (!mounted) return;
      final keepLabel = need.status == DeclaredNeedStatus.active
          ? 'Enviar mi valor actual '
                '(${formatQuantity(need.quantityBase!, need.baseUnit.majorUnit)})'
          : 'Mantener mi anulación';
      final choice = await showDialog<ConflictChoice>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Conflicto con el sindicato'),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'El sindicato tiene otra declaración de esta cuenta para el '
                'mismo producto y campaña (por ejemplo, desde otro teléfono). '
                'Usted decide; no se elige por fecha ni por llegada.',
              ),
            ),
            ListTile(
              title: Text(keepLabel),
              onTap: () =>
                  Navigator.pop(dialogContext, ConflictChoice.keepMine),
            ),
            ListTile(
              title: const Text('Retirar mi declaración'),
              onTap: () =>
                  Navigator.pop(dialogContext, ConflictChoice.withdraw),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      await _store.resolveConflict(needId: need.id, choice: choice, view: view);
      if (mounted) {
        showSuccess(context, _savedMessage('Decisión guardada', 'la'));
      }
      _afterEnqueue();
    } on Object catch (error) {
      if (mounted) showError(context, error);
    }
  }

  /// Estado del envío en palabras (C-03): «Guardada, pendiente de envío»,
  /// «Enviada, sin confirmación», «Aceptada por el sindicato: fecha»,
  /// «Rechazada por el sindicato: explicación», «En conflicto: decida
  /// usted», «Pausada: el sindicato no autorizó esta cuenta»… El código
  /// técnico no se
  /// muestra aquí; está en el detalle de Sincronización.
  String _syncLabel(DeclaredNeed need) {
    final status = need.syncStatus;
    if (status == null) return 'Sin envío';
    final phrase = outboxStatusPhrase(
      status,
      attempts: need.syncAttempts,
      feminine: true,
      conflictResolved: need.conflictResolved,
    );
    final candidate = syncCodeExplanation(need.syncCode);
    // La pausa por autorización ya se explica en la frase de estado; una
    // explicación idéntica a la frase tampoco añade nada.
    final explanation = candidate == phrase ? null : candidate;
    return switch (status) {
      OutboxStatus.acked =>
        need.syncAckedAt == null
            ? phrase
            : '$phrase: ${formatDate(need.syncAckedAt)}',
      OutboxStatus.rejected || OutboxStatus.failed =>
        explanation == null ? phrase : '$phrase: $explanation',
      OutboxStatus.conflict || OutboxStatus.authPaused => phrase,
      _ => explanation == null ? phrase : '$phrase · $explanation',
    };
  }

  @override
  Widget build(BuildContext context) {
    // Un ciclo del worker que no salió de esta pantalla (temporizador,
    // reconexión, «Sincronizar ahora») también cambia el estado de envío. Lo
    // último de cada ciclo es publicar el resumen nuevo: entonces se relee la
    // lista. Visto en el POCO: la necesidad seguía «Pendiente» después del ACK
    // hasta volver a entrar.
    ref.listen<SyncState>(syncControllerProvider, (previous, next) {
      if (previous != null && !identical(previous.summary, next.summary)) {
        _reload();
      }
    });
    // C-02: el motivo por el que el worker no envía (sin acceso verificado,
    // otra cuenta, 403, 422, sin red) se muestra aquí, no sólo en
    // Sincronización.
    return _page(ref.watch(syncControllerProvider));
  }

  Widget _page(SyncState sync) => PageFrame(
    title: 'Necesidad declarada',
    subtitle:
        'Lo que usted solicita al sindicato para una campaña. No cambia su '
        'inventario.',
    action: FilledButton.icon(
      onPressed: _declare,
      icon: const Icon(Icons.add),
      label: const Text('Declarar'),
    ),
    child: FutureBuilder<List<DeclaredNeed>>(
      future: needs,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sync.message != null) ...[
              SyncNoticeCard(
                message: sync.message!,
                busy: sync.busy,
                onSyncNow: _syncNow,
              ),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push('/sindicato/vinculos'),
                icon: const Icon(Icons.link),
                label: const Text('Vincular con el sindicato'),
              ),
            ),
            if (list.isEmpty)
              const EmptyState(
                icon: Icons.playlist_add,
                message: 'Todavía no declaró ninguna necesidad.',
              )
            else
              Card(
                child: Column(
                  children: [
                    for (final need in list)
                      ListTile(
                        title: Text(
                          '${need.productName} · ${need.campaignName}',
                        ),
                        subtitle: Text(
                          '${need.status == DeclaredNeedStatus.active ? formatQuantity(need.quantityBase!, need.baseUnit.majorUnit) : 'Anulada'}'
                          ' · ${_syncLabel(need)}',
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Opciones de la necesidad',
                          onSelected: (value) => switch (value) {
                            'edit' => _edit(need),
                            'withdraw' => _withdraw(need),
                            'resolve' => _resolve(need),
                            _ => _history(need),
                          },
                          itemBuilder: (_) => [
                            if (need.needsResolution)
                              const PopupMenuItem(
                                value: 'resolve',
                                child: Text('Resolver conflicto…'),
                              ),
                            PopupMenuItem(
                              value: 'edit',
                              child: Text(
                                need.status == DeclaredNeedStatus.active
                                    ? 'Cambiar cantidad…'
                                    : 'Declarar de nuevo…',
                              ),
                            ),
                            if (need.status == DeclaredNeedStatus.active)
                              const PopupMenuItem(
                                value: 'withdraw',
                                child: Text('Anular'),
                              ),
                            const PopupMenuItem(
                              value: 'history',
                              child: Text('Historial'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _DeclarationDraft {
  const _DeclarationDraft(
    this.date,
    this.campaignName,
    this.product,
    this.quantityBase,
  );
  final DateTime date;
  final String campaignName;
  final DeclarableProduct product;
  final int quantityBase;
}

/// Fecha de referencia → campaña (exactamente una, vinculada); producto
/// vinculado; cantidad total en L o KG.
class _DeclarationDialog extends StatefulWidget {
  const _DeclarationDialog({required this.store, required this.products});
  final DeclaredNeedStore store;
  final List<DeclarableProduct> products;

  @override
  State<_DeclarationDialog> createState() => _DeclarationDialogState();
}

class _DeclarationDialogState extends State<_DeclarationDialog> {
  DateTime date = DateTime.now();
  CampaignForDate? campaign;
  DeclarableProduct? product;
  final quantity = TextEditingController();
  String? quantityError;

  @override
  void initState() {
    super.initState();
    _resolveCampaign();
  }

  @override
  void dispose() {
    quantity.dispose();
    super.dispose();
  }

  Future<void> _resolveCampaign() async {
    final resolved = await widget.store.campaignFor(date);
    if (mounted) setState(() => campaign = resolved);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      date = picked;
      campaign = null;
    });
    await _resolveCampaign();
  }

  void _submit() {
    final chosen = product;
    final resolved = campaign;
    if (chosen == null || resolved == null || !resolved.isUsable) return;
    final parsed = parseBaseQuantity(quantity.text);
    if (!parsed.isValid) {
      setState(() => quantityError = parsed.message);
      return;
    }
    Navigator.pop(
      context,
      _DeclarationDraft(date, resolved.name!, chosen, parsed.base!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolved = campaign;
    return AlertDialog(
      title: const Text('Declarar necesidad'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(
                'Fecha de referencia: ${formatDate(date.toIso8601String())}',
              ),
              subtitle: Text(
                resolved == null ? 'Buscando la campaña…' : resolved.message,
              ),
              onTap: _pickDate,
            ),
            DropdownButtonFormField<DeclarableProduct>(
              initialValue: product,
              decoration: const InputDecoration(labelText: 'Producto'),
              items: [
                for (final option in widget.products)
                  DropdownMenuItem(value: option, child: Text(option.name)),
              ],
              onChanged: (value) => setState(() => product = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Cantidad total',
                suffixText: product?.baseUnit.majorUnit,
                helperText: 'Cero es una declaración válida.',
                errorText: quantityError,
              ),
              onChanged: (_) => setState(() => quantityError = null),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: product != null && resolved != null && resolved.isUsable
              ? _submit
              : null,
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.unit, this.initialBase});
  final String unit;
  final int? initialBase;
  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final TextEditingController controller = TextEditingController(
    text: widget.initialBase == null
        ? ''
        : formatForInput(widget.initialBase! / baseUnitsPerMajor),
  );
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nueva cantidad total'),
    content: TextField(
      controller: controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Cantidad total',
        suffixText: widget.unit,
        errorText: error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final parsed = parseBaseQuantity(controller.text);
          if (!parsed.isValid) {
            setState(() => error = parsed.message);
            return;
          }
          Navigator.pop(context, parsed.base);
        },
        child: const Text('Continuar'),
      ),
    ],
  );
}
