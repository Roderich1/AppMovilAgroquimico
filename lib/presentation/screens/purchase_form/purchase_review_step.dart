import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../domain/campaign_calendar.dart';
import '../../../domain/money.dart';
import '../../theme/agro_theme.dart';
import '../../widgets/adaptive_entity_picker.dart';
import '../../widgets/agro_ui.dart';
import '../../widgets/common.dart';
import '../../widgets/provider_payment_fields.dart';
import 'purchase_form_notifier.dart';
import 'purchase_form_state.dart';

String _recipientSummary(
  PurchaseLineData line,
  PurchaseFormState state,
  String unit,
  String ownerName,
) {
  if (state.personalOwnerId != null) return 'Para: $ownerName';
  return switch (line.allocationMode) {
    AllocationMode.single => 'Para: ${state.personName(line.singlePersonId)}',
    AllocationMode.split =>
      'Repartida: ${line.allocations.map((a) => '${state.personName(a.personId)} ${formatQuantity(tryParseBase(a.quantityText) ?? 0, unit)}').join(' · ')}',
    null => 'Pendiente de destinatario',
  };
}

List<Widget> buildPurchaseReviewStep(
  BuildContext context, {
  required PurchaseFormState state,
  required PurchaseCatalogs data,
  required PurchaseFormControllers controllers,
  required PurchaseFormNotifier notifier,
  required Future<void> Function(ImageSource source) onPickImage,
  required VoidCallback onEdited,
}) {
  final ownerName = state.ownerName() ?? 'Titular';
  final supplierName =
      data.suppliers
          .where((row) => row['id'] == state.supplierId)
          .firstOrNull?['name']
          ?.toString() ??
      '';
  String productName(int? id) => state.productOf(id)?['name']?.toString() ?? '';
  String productUnit(int? id) => state.productOf(id)?['unit']?.toString() ?? '';

  return [
    Semantics(
      header: true,
      child: const Text('Revise y confirme', style: AgroText.h1),
    ),
    const SizedBox(height: 12),
    Container(
      key: const Key('purchase-review'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AgroColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            children: [
              Text(
                supplierName,
                key: const Key('purchase-review-supplier'),
                style: AgroText.value,
              ),
              Text(
                state.personalOwnerId == null
                    ? purchaseDayLabel(state.effectiveDay)
                    : '${purchaseDayLabel(state.effectiveDay)} · '
                          'entra a su almacén',
                key: const Key('purchase-review-date'),
                style: AgroText.detail,
              ),
            ],
          ),
          const Divider(height: 24),
          for (var index = 0; index < state.lines.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AmountAside(
                amount: formatBob(state.lines[index].subtotalBob),
                amountKey: Key('purchase-review-subtotal-$index'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${productName(state.lines[index].productId)} · '
                      '${formatQuantity(state.lines[index].quantityBase, productUnit(state.lines[index].productId))}',
                      key: Key('purchase-review-line-$index'),
                      style: const TextStyle(
                        fontSize: 16,
                        height: 22 / 16,
                        fontWeight: FontWeight.w700,
                        color: AgroColors.ink,
                      ),
                    ),
                    if (state.personalOwnerId == null)
                      Text(
                        _recipientSummary(
                          state.lines[index],
                          state,
                          productUnit(state.lines[index].productId),
                          ownerName,
                        ),
                        key: Key('purchase-review-recipient-$index'),
                        style: AgroText.detail,
                      ),
                    if (lotDataSummary(state.lines[index]) case final lot?)
                      Text(
                        lot,
                        key: Key('purchase-review-lot-$index'),
                        style: AgroText.detail,
                      ),
                  ],
                ),
              ),
            ),
          const Divider(height: 14),
          TotalLine(
            label:
                'Total · ${state.lines.length} '
                '${state.lines.length == 1 ? 'producto' : 'productos'}',
            amount: formatBob(state.totalBob),
            amountKey: const Key('purchase-total'),
          ),
        ],
      ),
    ),
    const SizedBox(height: 20),
    Semantics(
      header: true,
      child: const Text(
        '¿Ya pagó al proveedor?',
        key: Key('purchase-paid-question'),
        style: AgroText.h2,
      ),
    ),
    const SizedBox(height: 10),
    ChoiceCards<bool>(
      key: const Key('purchase-paid-choice'),
      semanticLabel: 'Pago al proveedor',
      options: const [
        ChoiceCardOption(
          true,
          'Sí, pagué todo',
          Icons.payments_outlined,
          key: Key('purchase-paid-yes'),
        ),
        ChoiceCardOption(
          false,
          'Todavía no',
          Icons.schedule_outlined,
          key: Key('purchase-paid-no'),
        ),
      ],
      selected: state.paidInFull,
      onChanged: state.saving ? null : notifier.setPaidInFull,
    ),
    const SizedBox(height: 12),
    switch (state.paidInFull) {
      true => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            key: const Key('purchase-payer-owner'),
            children: [
              const Icon(Icons.check_circle_outline, color: AgroColors.link),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Paga el titular: $ownerName',
                  style: AgroText.question.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ProviderPaymentFields(
            method: state.paymentMethod,
            onMethodChanged: notifier.setPaymentMethod,
            day: state.effectivePaymentDay,
            dayHint: state.effectivePaymentDay == localDay(DateTime.now())
                ? ' (hoy)'
                : state.paymentDay == null
                ? ' (el día de la compra)'
                : '',
            onDayChanged: notifier.setPaymentDay,
            enabled: !state.saving,
          ),
        ],
      ),
      false when state.personalOwnerId != null => NoticeBox(
        key: const Key('purchase-no-payment'),
        icon: Icons.schedule_outlined,
        tone: NoticeTone.warning,
        text:
            'Esta compra quedará por pagar: ${formatBob(state.totalBob).trim()} con '
            '$supplierName. Podrá pagarlo después desde Registrar › Pago '
            'a un proveedor.',
      ),
      false => const NoticeBox(
        key: Key('purchase-no-payment'),
        icon: Icons.schedule_outlined,
        text:
            'La compra queda sin pago. Puede anotarlo después en Actividad › '
            'Compras › Lista de compras, con «Registrar pago al proveedor» '
            'en la compra.',
      ),
      null => const Text(
        'Elija una opción para poder confirmar.',
        key: Key('purchase-paid-pending'),
        style: AgroText.detail,
      ),
    },
    const SizedBox(height: 16),
    AgroGroup(
      children: [
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('purchase-details'),
            tilePadding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
            shape: const Border(),
            collapsedShape: const Border(),
            iconColor: AgroColors.ink,
            collapsedIconColor: AgroColors.muted,
            title: const Text(
              'Factura, notas y campaña (opcional)',
              style: TextStyle(
                fontSize: 15,
                height: 20 / 15,
                fontWeight: FontWeight.w500,
                color: AgroColors.ink,
              ),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            children: [
              TextField(
                controller: controllers.invoiceNumber,
                onChanged: (text) {
                  notifier.setInvoiceNumber(text);
                  onEdited();
                },
                decoration: const InputDecoration(labelText: 'N.º de factura'),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => onPickImage(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Cámara'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => onPickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galería'),
                  ),
                  if (state.invoiceImage != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(state.invoiceImage!.path),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controllers.notes,
                onChanged: (text) {
                  notifier.setNotes(text);
                  onEdited();
                },
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notas'),
              ),
              const SizedBox(height: 10),
              _campaignDropdown(
                data.campaigns
                    .where((row) => row['status'] == 'ACTIVE')
                    .toList(),
                state.campaignId,
                notifier.setCampaignId,
              ),
            ],
          ),
        ),
      ],
    ),
  ];
}

Widget _campaignDropdown(
  List<Map<String, Object?>> rows,
  int? value,
  ValueChanged<int?> onChanged,
) {
  final selected = rows.where((row) => row['id'] == value).firstOrNull;
  return AdaptiveEntityPicker<Map<String, Object?>>(
    label: 'Campaña',
    items: rows,
    value: selected,
    labelOf: (row) => row['name']! as String,
    onChanged: (row) => onChanged(row?['id'] as int?),
  );
}
