/// Textos de Cuentas (D-04, decisión del autor del 2026-10-27).
///
/// Viven aquí una sola vez para que la lista, el detalle, el diálogo de pago y
/// la exportación digan exactamente lo mismo
/// (`docs/architecture/D04_E15_CUENTAS_IMPUTACION_Y_COSTO_PROPIO.md` §2.3 a
/// §2.6).
library;

import 'account_ledger.dart';
import 'campaign_calendar.dart';
import 'money.dart';

/// Importe sin el espacio final de `formatBob`: «81,00 Bs».
String bob(int minor) => formatBob(minor).trim();

String _date(String day) => displayDay(day);

/// Línea 1 de la tarjeta y del desglose: cargos, revertidos y aplicados.
String chargesLine(CampaignDebt debt, {String? campaignName}) {
  if (!debt.hasCharges) return 'Sin cargos.';
  final label = campaignName == null ? 'Cargos' : 'Cargos de $campaignName';
  return [
    '$label ${bob(debt.chargesMinor)}',
    if (debt.reversedMinor > 0) 'revertidos ${bob(debt.reversedMinor)}',
    'pagos aplicados ${bob(debt.appliedMinor)}',
  ].join(' · ');
}

/// Línea 2 de la tarjeta con «Todas las campañas».
String pendingAndCreditLine(PersonAccount account) =>
    'Deuda pendiente ${bob(account.pendingMinor)} · '
    'a favor (no aplicado a deuda) ${bob(account.creditMinor)}';

String netLine(PersonAccount account) =>
    'Saldo neto · todas las campañas ${bob(account.netMinor)}';

/// Línea 3 de la tarjeta filtrada, sólo si F ≠ 0.
String? unattributedCreditLine(PersonAccount account) =>
    account.creditMinor == 0
    ? null
    : 'A favor (no aplicado a deuda) ${bob(account.creditMinor)} '
          '(sin campaña)';

const String netCaptionAll = 'Saldo neto · todas las campañas';

String pendingCaption(String campaignName) =>
    'Deuda pendiente por origen · $campaignName';

/// Composición de F en el desglose: sólo los términos distintos de cero.
String? creditCompositionLine(PersonAccount account) {
  final parts = [
    if (account.unappliedMinor != 0)
      'pagos sin imputar ${bob(account.unappliedMinor)}',
    if (account.releasedMinor != 0)
      'liberado por reversión ${bob(account.releasedMinor)}',
    if (account.compensationMinor != 0)
      'otros ajustes ${bob(-account.compensationMinor)}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Línea de una campaña en «Deuda pendiente por origen (a hoy)».
String originDebtLine(String campaignName, CampaignDebt debt) => [
  '$campaignName: cargos ${bob(debt.chargesMinor)}',
  if (debt.reversedMinor > 0) 'revertidos ${bob(debt.reversedMinor)}',
  'pagos aplicados ${bob(debt.appliedMinor)}',
  'pendiente ${bob(debt.pendingMinor)}',
].join(' · ');

String releasedLine(String campaignName, CampaignDebt debt) =>
    '${bob(debt.releasedMinor)} imputados a cargos revertidos de '
    '$campaignName quedan a favor';

/// Campaña del asiento (§2.5): en los créditos dice dónde se registró.
String entryCampaignText(
  AccountLedger ledger,
  PersonAccount account,
  LedgerEntry entry,
) {
  if (account.classOf(entry) == LedgerEntryClass.credit) {
    return entry.campaignId == null
        ? 'registrado sin campaña'
        : 'registrado en ${ledger.campaignName(entry.campaignId)}';
  }
  return entry.campaignId == null
      ? 'sin campaña'
      : ledger.campaignName(entry.campaignId);
}

/// «Imputado: Verano 2026 81,00 Bs · Invierno 2026 19,00 Bs»: suma por
/// campaña de origen, en el orden FIFO en que se imputó.
String? imputedText(
  AccountLedger ledger,
  Iterable<({int? campaignId, int amountMinor})> parts,
) {
  final order = <int?>[];
  final sums = <int?, int>{};
  for (final part in parts) {
    if (!sums.containsKey(part.campaignId)) order.add(part.campaignId);
    sums[part.campaignId] = (sums[part.campaignId] ?? 0) + part.amountMinor;
  }
  if (order.isEmpty) return null;
  return 'Imputado: ${[for (final id in order) '${ledger.campaignName(id)} ${bob(sums[id]!)}'].join(' · ')}';
}

/// Línea de estado de un asiento en el cronológico y en la exportación.
String statusText(
  AccountLedger ledger,
  PersonAccount account,
  LedgerEntry entry, {
  bool ownRecord = false,
}) {
  switch (account.classOf(entry)) {
    case LedgerEntryClass.charge:
      final charge = account.charges[entry.id]!;
      if (charge.isReversed) {
        return 'Revertido el ${_date(charge.reversalDay!)}';
      }
      if (ownRecord) return '';
      return charge.pendingMinor == 0
          ? 'Pagado'
          : 'Pendiente a hoy ${bob(charge.pendingMinor)}';
    case LedgerEntryClass.chargeReversal:
      final charge = account.charges[entry.reversalOfId];
      return charge == null
          ? ''
          : 'Revierte el cargo del ${_date(charge.entry.day)}';
    case LedgerEntryClass.creditCompensation:
      return 'Compensa un crédito anterior';
    case LedgerEntryClass.credit:
      final credit = account.credits[entry.id]!;
      final live = [
        for (final allocation in credit.allocations)
          if (!allocation.charge.isReversed)
            (
              campaignId: allocation.charge.entry.campaignId,
              amountMinor: allocation.amountMinor,
            ),
      ];
      final parts = <String>[
        ?imputedText(ledger, live),
        for (final allocation in credit.allocations)
          if (allocation.charge.isReversed)
            'Imputado a un cargo revertido '
                '(${ledger.campaignName(allocation.charge.entry.campaignId)}, '
                '${_date(allocation.charge.entry.day)}): '
                '${bob(allocation.amountMinor)}. Queda a favor.',
      ];
      final unapplied = credit.unappliedMinor;
      if (unapplied > 0) {
        if (entry.type == 'CREDIT_ADJUSTMENT' && credit.allocations.isEmpty) {
          parts.add(
            'Crédito sin cargo de origen registrado: ${bob(unapplied)} '
            '(queda a favor, sin campaña)',
          );
        } else if (credit.allocations.isEmpty) {
          parts.add(
            'Sin imputación registrada: ${bob(unapplied)} '
            '(queda a favor, sin campaña)',
          );
        } else {
          parts.add(
            'sin imputar ${bob(unapplied)} (queda a favor, sin campaña)',
          );
        }
      }
      return parts.join(' · ');
  }
}

/// Cabecera del cronológico.
String statementHeader(AccountStatement statement) {
  final period = statement.period;
  if (period == null)
    return 'Estado de cuenta cronológico · todas las campañas';
  final end = statement.periodClosed ? _date(period.endDay!) : 'hoy';
  return 'Estado de cuenta cronológico · período de ${period.name} '
      '(${_date(period.startDay)} – $end)';
}

String openingLabel(CampaignPeriod period) =>
    'Saldo al inicio del período (${_date(period.startDay)})';

String closingLabel(AccountStatement statement) => statement.periodClosed
    ? 'Saldo al cierre del período (${_date(statement.period!.endDay!)})'
    : 'Saldo a hoy';

/// Campaña de registro en el diálogo de pago (§2.4).
String registrationText(CampaignPeriod? campaign, DateTime now) {
  if (campaign == null) return 'Se registra sin campaña';
  if (campaign.status == 'CLOSED') {
    return 'Se registra en: ${campaign.name} (cerrada). En el estado '
        'cronológico aparecerá por su fecha, ${_date(localDay(now))}';
  }
  return 'Se registra en: ${campaign.name}';
}

String dialogNetText(int netMinor) {
  if (netMinor > 0)
    return 'Saldo neto · todas las campañas: debe ${bob(netMinor)}';
  if (netMinor < 0) {
    return 'Saldo neto · todas las campañas: a favor ${bob(-netMinor)}';
  }
  return 'Saldo neto · todas las campañas: al día';
}

const String dialogFifoText =
    'Se aplica primero a la deuda más antigua, de cualquier campaña.';

/// Resultado de registrar un pago o adelanto: lo escrito de verdad.
final class AccountPaymentResult {
  const AccountPaymentResult({
    required this.paymentId,
    required this.amountMinor,
    required this.advance,
    required this.imputed,
    required this.unappliedMinor,
  });

  final int paymentId;
  final int amountMinor;
  final bool advance;

  /// Imputaciones escritas, en orden FIFO, con la campaña de origen del cargo.
  final List<({int? campaignId, String campaignName, int amountMinor})> imputed;
  final int unappliedMinor;

  /// «Pago de 50,00 Bs registrado a X. Imputado: Verano 2026 50,00 Bs.»
  String message(String personName) {
    final buffer = StringBuffer(
      '${advance ? 'Adelanto' : 'Pago'} de ${bob(amountMinor)} '
      'registrado a $personName.',
    );
    if (imputed.isNotEmpty) {
      final order = <String>[];
      final sums = <String, int>{};
      for (final part in imputed) {
        if (!sums.containsKey(part.campaignName)) order.add(part.campaignName);
        sums[part.campaignName] =
            (sums[part.campaignName] ?? 0) + part.amountMinor;
      }
      buffer.write(
        ' Imputado: ${[for (final name in order) '$name ${bob(sums[name]!)}'].join(' · ')}.',
      );
    }
    if (unappliedMinor > 0) {
      buffer.write(' Sin imputar: ${bob(unappliedMinor)} (queda a favor).');
    }
    return buffer.toString();
  }
}
