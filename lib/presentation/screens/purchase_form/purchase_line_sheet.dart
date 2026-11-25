import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/campaign_calendar.dart';
import '../../../domain/inventory_alerts.dart' show expiryPickerRange;
import '../../../domain/models.dart';
import '../../../domain/money.dart';
import '../../../domain/operation_mode.dart';
import '../../../domain/repository_types.dart'
    show repositoryLotNumberLengthError;
import '../../../voice_draft/purchase/voice_purchase_draft.dart';
import '../../theme/agro_theme.dart';
import '../../voice/voice_form_dictation.dart';
import '../../widgets/adaptive_entity_picker.dart';
import '../../widgets/agro_ui.dart';
import '../../widgets/common.dart';
import 'purchase_form_notifier.dart';
import 'purchase_form_state.dart';
import 'purchase_items_step.dart'
    show purchaseAllocationStatus, purchaseVoiceMissingMarks;

/// Hoja inferior «Producto n» para editar una línea en el mismo borrador.
class PurchaseLineSheet extends StatelessWidget {
  const PurchaseLineSheet({
    super.key,
    required this.state,
    required this.data,
    required this.line,
    required this.index,
    required this.controllers,
    required this.notifier,
    required this.voice,
    required this.currentMode,
    required this.onCloseLine,
    required this.onAppendLine,
    required this.onOpenVoiceFromSheet,
    required this.onCreateProduct,
    required this.onCreatePerson,
    required this.onRemoveLine,
    required this.onEdited,
  });

  final PurchaseFormState state;
  final PurchaseCatalogs data;
  final PurchaseLineData line;
  final int index;
  final PurchaseLineControllers controllers;
  final PurchaseFormNotifier notifier;
  final VoiceFormDictation<VoicePurchaseDraft>? voice;
  final OperationMode? currentMode;
  final VoidCallback onCloseLine;
  final VoidCallback onAppendLine;
  final VoidCallback onOpenVoiceFromSheet;
  final Future<Map<String, Object?>?> Function() onCreateProduct;
  final Future<Map<String, Object?>?> Function() onCreatePerson;
  final VoidCallback onRemoveLine;
  final VoidCallback onEdited;

  @override
  Widget build(BuildContext context) => InPageSheet(
    key: Key('purchase-line-sheet-$index'),
    title: 'Producto ${index + 1}',
    closeKey: const Key('purchase-line-close'),
    onClose: onCloseLine,
    actions: [
      SecondaryActionButton(
        key: const Key('purchase-line-next'),
        label: 'Añadir otro',
        icon: Icons.add,
        onPressed: state.saving ? null : onAppendLine,
      ),
      PrimaryActionButton(
        key: const Key('purchase-line-done'),
        label: 'Listo',
        icon: Icons.check,
        iconFirst: true,
        onPressed: onCloseLine,
      ),
    ],
    children: _buildChildren(context),
  );

  Widget _lineMark(
    String field, {
    String? currentDisplay,
    bool showMark = true,
  }) => VoiceSlotMark(
    dictation: voice,
    slot: SlotRef.line(line.id, field),
    current: line.voiceFields(state.personalOwnerId == null)[field],
    currentDisplay: currentDisplay,
    showMark: showMark,
  );

  List<Widget> _buildChildren(BuildContext context) {
    final product = state.productOf(line.productId);
    final unit = product?['unit']?.toString() ?? '';
    final hasProduct = unit.isNotEmpty;
    final usd = line.currency == CurrencyCode.usd;
    final usedProductIds = {
      for (final other in state.lines)
        if (other.id != line.id && other.productId != null) other.productId!,
    };
    const suffixStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: AgroColors.muted,
    );
    final quantity = TextField(
      key: Key('purchase-quantity-$index'),
      controller: controllers.quantity,
      onChanged: (text) {
        notifier.setLineQuantity(line.id, text);
        onEdited();
      },
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: AgroText.input,
      decoration: InputDecoration(
        labelText: 'Cantidad comprada',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixText: unit.isEmpty ? null : unit,
        suffixStyle: suffixStyle,
        errorText: line.quantityError,
        errorMaxLines: 4,
      ),
    );
    final price = TextField(
      key: Key('purchase-price-$index'),
      controller: controllers.price,
      onChanged: (text) {
        notifier.setLinePrice(line.id, text);
        onEdited();
      },
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: AgroText.input,
      decoration: InputDecoration(
        labelText: hasProduct ? 'Precio por $unit' : 'Precio por unidad',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        suffixText: usd ? 'USD' : 'Bs',
        suffixStyle: suffixStyle,
        errorText: line.priceError,
        errorMaxLines: 4,
      ),
    );
    return [
      if (state.lineProblem != null) ...[
        Semantics(
          liveRegion: true,
          child: NoticeBox(
            key: const Key('purchase-line-problem'),
            tone: NoticeTone.danger,
            text: state.lineProblem!,
          ),
        ),
        const SizedBox(height: 12),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: PillButton(
          key: const Key('purchase-line-voz'),
          icon: Icons.mic_none_outlined,
          label: 'Completar por voz',
          onPressed: state.saving ? null : onOpenVoiceFromSheet,
        ),
      ),
      const SizedBox(height: 12),
      AgroGroup(
        children: [
          AdaptiveEntityPicker<Map<String, Object?>>(
            rowStyle: true,
            label: 'Producto',
            items: data.products
                .where(
                  (row) =>
                      !usedProductIds.contains(row['id']) ||
                      row['id'] == line.productId,
                )
                .toList(),
            value: product,
            labelOf: (row) => row['name']! as String,
            secondaryOf: (row) => row['unit']! as String,
            autoSelectSingle: false,
            badge: VoiceMarkBadge(
              dictation: voice,
              slot: SlotRef.line(line.id, 'product'),
              current: line.productId,
            ),
            onChanged: (row) {
              notifier.setLineProduct(line.id, row?['id'] as int?);
              onEdited();
            },
            createLabel: 'Crear producto',
            onCreate: onCreateProduct,
          ),
        ],
      ),
      _lineMark(
        'product',
        currentDisplay: product?['name']?.toString(),
        showMark: false,
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final floating =
              (Theme.of(context).textTheme.bodyLarge ??
                      const TextStyle(fontSize: 16))
                  .copyWith(fontSize: 12);
          final widest = [
            'Cantidad comprada',
            hasProduct ? 'Precio por $unit' : 'Precio por unidad',
          ].map((t) => measureText(context, t, floating)).fold(0.0, math.max);
          if (constraints.maxWidth >= 2 * (widest + 40) + 10) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: quantity),
                const SizedBox(width: 10),
                Expanded(child: price),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [quantity, const SizedBox(height: 10), price],
          );
        },
      ),
      _lineMark('quantity'),
      _lineMark('price', currentDisplay: line.priceText),
      const SizedBox(height: 12),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          SizedBox(
            width: 168,
            child: SegmentToggle<CurrencyCode>(
              key: Key('purchase-currency-$index'),
              semanticLabel: 'Moneda',
              height: 44,
              options: [
                ToggleOption(
                  CurrencyCode.bob,
                  'BOB',
                  key: Key('purchase-currency-bob-$index'),
                ),
                ToggleOption(
                  CurrencyCode.usd,
                  'USD',
                  key: Key('purchase-currency-usd-$index'),
                ),
              ],
              selected: line.currency,
              onChanged: (value) {
                if (value == line.currency) return;
                notifier.setLineCurrency(line.id, value);
                onEdited();
              },
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Subtotal', style: AgroText.detail),
              Text(
                formatBob(line.subtotalBob),
                key: Key('purchase-line-subtotal-$index'),
                style: AgroText.total.copyWith(fontSize: 24, height: 30 / 24),
              ),
            ],
          ),
        ],
      ),
      _lineMark('currency', currentDisplay: line.currency.name.toUpperCase()),
      if (usd) ...[
        const SizedBox(height: 12),
        TextField(
          controller: controllers.fx,
          onChanged: (text) {
            notifier.setLineFx(line.id, text);
            onEdited();
          },
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'TC Bs/USD',
            floatingLabelBehavior: FloatingLabelBehavior.always,
            errorText: line.fxError,
            errorMaxLines: 4,
          ),
        ),
        _lineMark('fx', currentDisplay: line.fxText),
        if (hasProduct)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Costo en bolivianos: ${formatBob(line.unitBob)}/$unit',
              style: AgroText.detail,
            ),
          ),
      ],
      ...purchaseVoiceMissingMarks(
        voice,
        line,
        line.voiceFields(state.personalOwnerId == null),
      ),
      const SizedBox(height: 16),
      if (state.personalOwnerId == null) ...[
        ..._recipientSection(unit),
        _lineMark(
          'recipient',
          currentDisplay: line.singlePersonId == null
              ? null
              : state.personName(line.singlePersonId),
        ),
      ],
      const SizedBox(height: 12),
      AgroGroup(
        children: [
          _ExpiryRow(
            index: index,
            line: line,
            onExpiryChanged: (day) {
              notifier.setLineExpiry(line.id, day);
              onEdited();
            },
          ),
          _PackageDataSection(
            index: index,
            line: line,
            lotController: controllers.lotNumber,
            onChanged: (text) {
              notifier.setLineLotNumber(line.id, text);
              onEdited();
            },
          ),
        ],
      ),
      if (state.lines.length > 1) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: Key('purchase-line-remove-$index'),
            onPressed: state.saving ? null : onRemoveLine,
            style: TextButton.styleFrom(foregroundColor: AgroColors.danger),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Quitar este producto'),
          ),
        ),
      ],
    ];
  }

  List<Widget> _recipientSection(String unit) {
    final people = data.people;
    final canCreate = state.canCreatePeople(currentMode);
    return [
      const Text('¿Para quién es?', style: AgroText.question),
      const SizedBox(height: 8),
      SegmentToggle<AllocationMode>(
        key: Key('purchase-alloc-mode-$index'),
        semanticLabel: 'Para quién es',
        options: [
          ToggleOption(
            AllocationMode.single,
            'Una persona',
            key: Key('purchase-alloc-single-$index'),
          ),
          ToggleOption(
            AllocationMode.split,
            'Repartir entre varias',
            key: Key('purchase-alloc-split-$index'),
          ),
        ],
        selected: line.allocationMode,
        onChanged: (mode) {
          if (mode == line.allocationMode) return;
          notifier.setLineAllocationMode(line.id, mode);
          onEdited();
        },
      ),
      const SizedBox(height: 10),
      switch (line.allocationMode) {
        null => Text(
          'Elija una opción para indicar a quién va este producto.',
          key: Key('purchase-alloc-pending-$index'),
          style: AgroText.detail,
        ),
        AllocationMode.single => AgroGroup(
          children: [
            AdaptiveEntityPicker<Map<String, Object?>>(
              rowStyle: true,
              label: 'Persona',
              displayLabel: line.quantityBase > 0
                  ? 'Recibe toda la cantidad: '
                        '${formatQuantity(line.quantityBase, unit)}'
                  : 'Persona que recibe',
              displayLabelKey: Key('purchase-alloc-derived-$index'),
              items: people,
              value: people
                  .where((person) => person['id'] == line.singlePersonId)
                  .firstOrNull,
              labelOf: (person) => person['name']! as String,
              secondaryOf: state.personRole,
              autoSelectSingle: false,
              onChanged: (person) {
                notifier.setLineSinglePerson(line.id, person?['id'] as int?);
                onEdited();
              },
              createLabel: canCreate ? 'Agregar persona' : null,
              onCreate: canCreate ? onCreatePerson : null,
            ),
          ],
        ),
        AllocationMode.split => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final allocation in line.allocations)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _AllocationRow(
                  onRemove: line.allocations.length > 2
                      ? () {
                          notifier.removeAllocationRow(line.id, allocation.id);
                          onEdited();
                        }
                      : null,
                  children: [
                    Expanded(
                      flex: 3,
                      child: AgroGroup(
                        children: [
                          AdaptiveEntityPicker<Map<String, Object?>>(
                            rowStyle: true,
                            label: 'Persona',
                            items: people,
                            value: people
                                .where(
                                  (person) =>
                                      person['id'] == allocation.personId,
                                )
                                .firstOrNull,
                            labelOf: (person) => person['name']! as String,
                            secondaryOf: state.personRole,
                            autoSelectSingle: false,
                            onChanged: (person) {
                              notifier.setAllocationPerson(
                                line.id,
                                allocation.id,
                                person?['id'] as int?,
                              );
                              onEdited();
                            },
                            createLabel: canCreate ? 'Agregar persona' : null,
                            onCreate: canCreate ? onCreatePerson : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: controllers.allocationQuantity(
                          allocation.id,
                          allocation.quantityText,
                        ),
                        onChanged: (text) {
                          notifier.setAllocationQuantity(
                            line.id,
                            allocation.id,
                            text,
                          );
                          onEdited();
                        },
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Cantidad',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          suffixText: unit.isEmpty ? null : unit,
                          errorText: allocation.quantityError,
                          errorMaxLines: 4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(
                  purchaseAllocationStatus(line, state),
                  key: Key('purchase-alloc-status-$index'),
                  style: AgroText.detail.copyWith(fontWeight: FontWeight.w700),
                ),
                TextButton.icon(
                  key: Key('purchase-alloc-add-$index'),
                  onPressed: () {
                    notifier.addAllocationRow(line.id);
                    onEdited();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir persona'),
                ),
              ],
            ),
          ],
        ),
      },
    ];
  }
}

class _ExpiryRow extends StatelessWidget {
  const _ExpiryRow({
    required this.index,
    required this.line,
    required this.onExpiryChanged,
  });

  final int index;
  final PurchaseLineData line;
  final ValueChanged<String?> onExpiryChanged;

  Future<void> _pickExpiry(BuildContext context) async {
    final now = DateTime.now();
    final current = line.expiryDay == null
        ? null
        : startOfLocalDay(line.expiryDay!);
    final range = expiryPickerRange(current, now);
    final picked = await showDatePicker(
      context: context,
      initialDate: range.initial,
      firstDate: range.first,
      lastDate: range.last,
      helpText: 'Fecha de vencimiento',
    );
    if (picked == null) return;
    onExpiryChanged(localDay(picked));
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: ValueRow(
          key: Key('purchase-expiry-$index'),
          label: 'Vencimiento (opcional)',
          value: line.expiryDay == null
              ? null
              : 'Vence el ${displayDay(line.expiryDay!)}',
          placeholder: 'Elegir fecha',
          trailing: const Icon(Icons.event_outlined, color: AgroColors.muted),
          onTap: () => _pickExpiry(context),
        ),
      ),
      if (line.expiryDay != null)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: IconButton(
            key: Key('purchase-expiry-clear-$index'),
            tooltip: 'Quitar la fecha de vencimiento',
            onPressed: () => onExpiryChanged(null),
            icon: const Icon(Icons.close),
          ),
        ),
    ],
  );
}

class _PackageDataSection extends StatelessWidget {
  const _PackageDataSection({
    required this.index,
    required this.line,
    required this.lotController,
    required this.onChanged,
  });

  final int index;
  final PurchaseLineData line;
  final TextEditingController lotController;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final number = line.lotNumberValue;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: Key('purchase-lot-data-$index'),
        initiallyExpanded: line.lotNumberText.trim().isNotEmpty,
        tilePadding: const EdgeInsets.fromLTRB(16, 2, 10, 2),
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: AgroColors.ink,
        collapsedIconColor: AgroColors.muted,
        childrenPadding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        title: const Text(
          'Más datos del envase',
          style: TextStyle(
            fontSize: 15,
            height: 20 / 15,
            fontWeight: FontWeight.w500,
            color: AgroColors.ink,
          ),
        ),
        subtitle: number == null
            ? null
            : Text(packageLotText(number), style: AgroText.detail),
        children: [
          TextField(
            key: Key('purchase-lot-number-$index'),
            controller: lotController,
            onChanged: onChanged,
            decoration: InputDecoration(
              labelText: 'Lote del fabricante (opcional)',
              helperText:
                  'Tal como figura en el envase. Si no tiene, '
                  'déjelo vacío.',
              helperMaxLines: 3,
              counterText: lotNumberCounter(line.lotNumberText),
              errorText: repositoryLotNumberLengthError(line.lotNumberText),
              errorMaxLines: 3,
            ),
          ),
        ],
      ),
    );
  }
}

class _AllocationRow extends StatelessWidget {
  const _AllocationRow({required this.children, this.onRemove});

  final List<Widget> children;
  final VoidCallback? onRemove;
  static const double rowMinWidth = 480;

  @override
  Widget build(BuildContext context) {
    final remove = onRemove == null
        ? null
        : IconButton(
            tooltip: 'Quitar asignación',
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          );
    final person = (children.first as Expanded).child;
    final quantity = (children.last as Expanded).child;
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= rowMinWidth
          ? Row(children: [...children, ?remove])
          : Column(
              children: [
                person,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: quantity),
                    ?remove,
                  ],
                ),
              ],
            ),
    );
  }
}
