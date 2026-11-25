import 'package:flutter/material.dart';

import '../../../domain/campaign_calendar.dart' show displayDay;
import '../../../domain/models.dart';
import '../../../domain/money.dart';
import '../../../voice_draft/purchase/voice_purchase_draft.dart';
import '../../theme/agro_theme.dart';
import '../../voice/voice_form_dictation.dart';
import '../../widgets/adaptive_entity_picker.dart';
import '../../widgets/agro_ui.dart';
import '../../widgets/common.dart';
import 'purchase_form_state.dart';

const _voiceLineFields = [
  'product',
  'quantity',
  'price',
  'currency',
  'fx',
  'recipient',
];

/// Cómo va el destinatario de [line] (paso 1 y tarjeta resumen).
String purchaseAllocationStatus(
  PurchaseLineData line,
  PurchaseFormState state,
) {
  final unit = state.productOf(line.productId)?['unit']?.toString() ?? '';
  if (state.personalOwnerId != null) {
    return line.quantityBase <= 0 ? 'Pendiente de cantidad' : '';
  }
  switch (line.allocationMode) {
    case null:
      return 'Pendiente de destinatario';
    case AllocationMode.single:
      if (line.singlePersonId == null) return 'Pendiente de destinatario';
      if (line.quantityBase <= 0) return 'Pendiente de cantidad';
      return 'Para: ${state.personName(line.singlePersonId)}';
    case AllocationMode.split:
      if (line.quantityBase <= 0) return 'Pendiente de cantidad';
      if (line.allocations.any((allocation) => allocation.personId == null)) {
        return 'Pendiente de persona';
      }
      final pending = line.quantityBase - line.assignedBase;
      if (pending > 0) {
        return 'Pendiente ${formatQuantity(pending, unit)}';
      }
      if (pending < 0) {
        return 'Excede en ${formatQuantity(-pending, unit)}';
      }
      return 'Repartida: ${line.allocations.map((a) => '${state.personName(a.personId)} ${formatQuantity(tryParseBase(a.quantityText) ?? 0, unit)}').join(' · ')}';
  }
}

/// «Falta» de los datos obligatorios en una línea que tocó la voz.
List<Widget> purchaseVoiceMissingMarks(
  VoiceFormDictation<VoicePurchaseDraft>? voice,
  PurchaseLineData line,
  Map<String, Object?> fields,
) {
  if (voice == null || !voice.touchesLine(line.id)) return const [];
  return [
    if (fields['product'] == null) const VoiceMissingMark(label: 'producto'),
    if (fields['quantity'] == null) const VoiceMissingMark(label: 'cantidad'),
    if (fields['price'] == null) const VoiceMissingMark(label: 'precio'),
  ];
}

List<Widget> buildPurchaseItemsStep({
  required PurchaseFormState state,
  required PurchaseCatalogs data,
  required VoiceFormDictation<VoicePurchaseDraft>? voice,
  required VoidCallback onOpenVoice,
  required VoidCallback onDismissVoiceBanner,
  required Future<Map<String, Object?>?> Function() onCreateSupplier,
  required ValueChanged<int?> onSupplierChanged,
  required VoidCallback onPickDate,
  required ValueChanged<int> onOpenLine,
  required VoidCallback onAddLine,
}) {
  final supplierName = data.suppliers
      .where((row) => row['id'] == state.supplierId)
      .firstOrNull?['name']
      ?.toString();
  final touchedAny = voice != null;
  final onlyBlank =
      state.lines.length == 1 &&
      state.lines.single.isBlank(
        touchedByVoice: touchedAny && voice.touchesLine(state.lines.single.id),
      );
  final filled = state.lines
      .where(
        (line) => !line.isBlank(
          touchedByVoice: touchedAny && voice.touchesLine(line.id),
        ),
      )
      .length;
  return [
    Semantics(
      header: true,
      child: const Text('¿Qué compró?', style: AgroText.h1),
    ),
    const SizedBox(height: 12),
    if (voice != null && state.voiceBanner && !state.showVoice) ...[
      VoiceResultBanner(
        dictation: voice,
        onDictateMore: state.saving ? null : onOpenVoice,
        onDismiss: onDismissVoiceBanner,
      ),
      const SizedBox(height: 12),
    ] else if (!state.showVoice) ...[
      Align(
        alignment: Alignment.centerLeft,
        child: PillButton(
          key: const Key('compra-completar-voz'),
          icon: Icons.mic_none_outlined,
          label: 'Completar por voz',
          onPressed: state.saving ? null : onOpenVoice,
        ),
      ),
      const SizedBox(height: 12),
    ],
    AgroGroup(
      children: [
        AdaptiveEntityPicker<Map<String, Object?>>(
          key: const Key('purchase-supplier'),
          rowStyle: true,
          label: 'Proveedor',
          items: data.suppliers,
          value: data.suppliers
              .where((row) => row['id'] == state.supplierId)
              .firstOrNull,
          labelOf: (row) => row['name']! as String,
          createLabel: 'Crear proveedor',
          onCreate: onCreateSupplier,
          badge: VoiceMarkBadge(
            dictation: voice,
            slot: const SlotRef.header('supplier'),
            current: state.supplierId,
          ),
          onChanged: (row) => onSupplierChanged(row?['id'] as int?),
        ),
        ValueRow(
          key: const Key('purchase-date'),
          label: 'Fecha de la compra',
          value: purchaseDayLabel(state.effectiveDay),
          onTap: state.saving ? null : onPickDate,
        ),
      ],
    ),
    VoiceSlotMark(
      dictation: voice,
      slot: const SlotRef.header('supplier'),
      current: state.supplierId,
      currentDisplay: supplierName,
      showMark: false,
    ),
    const SizedBox(height: 8),
    SectionHeader(
      title: 'Productos de esta compra',
      trailing: filled == 0 ? null : '$filled',
    ),
    const SizedBox(height: 10),
    if (!onlyBlank)
      for (var index = 0; index < state.lines.length; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _PurchaseLineCard(
            index: index,
            line: state.lines[index],
            state: state,
            voice: voice,
            onOpenLine: onOpenLine,
          ),
        ),
    DashedAddButton(
      key: const Key('purchase-add-line'),
      label: onlyBlank ? 'Añadir producto' : 'Añadir otro producto',
      onPressed: state.saving ? null : onAddLine,
    ),
  ];
}

class _PurchaseLineCard extends StatelessWidget {
  const _PurchaseLineCard({
    required this.index,
    required this.line,
    required this.state,
    required this.voice,
    required this.onOpenLine,
  });

  final int index;
  final PurchaseLineData line;
  final PurchaseFormState state;
  final VoiceFormDictation<VoicePurchaseDraft>? voice;
  final ValueChanged<int> onOpenLine;

  static String _priceText(PurchaseLineData line) =>
      line.currency == CurrencyCode.usd
      ? formatUsd(line.priceMinor)
      : formatBob(line.priceMinor);

  @override
  Widget build(BuildContext context) {
    final product = state.productOf(line.productId);
    final unit = product?['unit']?.toString() ?? '';
    final shared = state.personalOwnerId == null;
    final fields = line.voiceFields(shared);
    final v = voice;
    final pending =
        v != null &&
        _voiceLineFields.any((field) {
          final slot = SlotRef.line(line.id, field);
          return v.choiceFor(slot) != null || v.reviewFor(slot) != null;
        });
    final byVoice =
        v != null &&
        fields.entries.any(
          (e) => v.markFor(SlotRef.line(line.id, e.key), e.value) != null,
        );
    final amounts = [
      if (line.quantityBase > 0) formatQuantity(line.quantityBase, unit),
      if (line.priceMinor > 0) _priceText(line),
    ].join(' × ');
    final status = purchaseAllocationStatus(line, state);
    final subtitle = [
      if (amounts.isNotEmpty) amounts,
      if (status.isNotEmpty) status,
      if (line.expiryDay != null) 'Vence el ${displayDay(line.expiryDay!)}',
    ].join(' · ');
    final complete =
        line.quantityBase > 0 &&
        line.priceMinor > 0 &&
        (line.currency == CurrencyCode.bob ||
            (line.exchangeRateScaled ?? 0) > 0);
    return ItemCard(
      key: Key('purchase-line-$index'),
      title: product?['name']?.toString() ?? 'Producto ${index + 1}',
      subtitle: product == null
          ? 'Falta elegir el producto · $subtitle'
          : subtitle,
      amount: complete ? formatBob(line.subtotalBob) : null,
      attention: pending,
      semanticsHint: 'Abrir para editar',
      badge: byVoice && !pending
          ? const StatusBadge(label: 'Por voz', tone: BadgeTone.voice)
          : null,
      onTap: state.saving ? null : () => onOpenLine(line.id),
      footer: [
        ...purchaseVoiceMissingMarks(v, line, fields),
        for (final field in _voiceLineFields)
          VoiceSlotMark(
            dictation: v,
            slot: SlotRef.line(line.id, field),
            current: fields[field],
            currentDisplay: switch (field) {
              'product' => product?['name']?.toString(),
              'recipient' =>
                line.singlePersonId == null
                    ? null
                    : state.personName(line.singlePersonId),
              'currency' => line.currency.name.toUpperCase(),
              'price' => line.priceText,
              'fx' => line.fxText,
              _ => null,
            },
            showMark: false,
            writeOtherLabel: field == 'product' || field == 'recipient'
                ? 'Elegir otro'
                : 'Escribir otro valor',
            onWriteOther: state.saving ? null : () => onOpenLine(line.id),
          ),
      ],
    );
  }
}

/// Total del paso 1: evita mostrar un subtotal engañoso si falta algún dato.
class PurchaseItemsTotal extends StatelessWidget {
  const PurchaseItemsTotal({
    super.key,
    required this.state,
    required this.voice,
  });

  final PurchaseFormState state;
  final VoiceFormDictation<VoicePurchaseDraft>? voice;

  @override
  Widget build(BuildContext context) {
    const key = Key('purchase-items-total');
    final filled = state.lines
        .where(
          (line) => !line.isBlank(
            touchedByVoice: voice?.touchesLine(line.id) ?? false,
          ),
        )
        .toList();
    if (filled.isEmpty) {
      return const TotalLine(
        label: 'Total',
        amount: '—',
        muted: true,
        amountKey: key,
      );
    }
    final missing = filled.any((line) => line.priceMinor <= 0)
        ? 'un precio'
        : filled.any((line) => line.quantityBase <= 0)
        ? 'una cantidad'
        : filled.any(
            (line) =>
                line.currency == CurrencyCode.usd &&
                (line.exchangeRateScaled ?? 0) <= 0,
          )
        ? 'un tipo de cambio'
        : null;
    if (missing != null) {
      return TotalLine(
        label: 'Total · falta $missing',
        amount: '—',
        muted: true,
        amountKey: key,
      );
    }
    return TotalLine(
      label:
          'Total · ${filled.length} '
          '${filled.length == 1 ? 'producto' : 'productos'}',
      amount: formatBob(state.totalBob),
      amountKey: key,
    );
  }
}
