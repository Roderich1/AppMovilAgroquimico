/// Presentación de lotes y vencimientos de la ronda 2 de la sesión B
/// (decisiones del autor del 2026-11-12):
///
/// - el identificador interno del lote lo administra el sistema y no se
///   muestra en la vida diaria;
/// - el número del fabricante es opcional, real y secundario: sólo aparece
///   si existe, como «Lote del fabricante», y nunca se inventa;
/// - una referencia visual corta sólo cuando hace falta distinguir entradas
///   iguales a la vista (misma persona y misma fecha de compra): «entrada 1
///   de 2», derivada de la persona y la fecha, nunca presentada como lote;
/// - el aviso de vencimiento dice la cantidad afectada («1 L vence el
///   11/12/2026»), no sugiere que vence todo el producto.
///
/// Sólo presenta: recibe filas ya leídas y no decide reglas ni cálculos (la
/// clasificación de vencimientos es la de `inventory_alerts.dart`).
library;

import 'package:flutter/material.dart';

import '../../domain/inventory_alerts.dart';
import '../../domain/money.dart';
import '../theme/agro_theme.dart';

/// Rótulo del número que trae el envase (dato opcional y secundario).
const manufacturerLotLabel = 'Lote del fabricante';

/// Una cantidad es gramaticalmente singular sólo si es exactamente una
/// unidad («1 L vence»; «0,5 L vencen», «1,5 L vencen»).
bool _singular(int base) => base == baseUnitsPerMajor;

/// Parte de lo que hay con un mismo estado y fecha de vencimiento.
@immutable
class ExpiryPortion {
  const ExpiryPortion({
    required this.status,
    required this.day,
    required this.quantityBase,
  });

  final ExpiryStatus status;

  /// Día civil `aaaa-mm-dd`; nulo sin fecha registrada.
  final String? day;
  final int quantityBase;

  /// Pide atención: vencido, vence hoy o por vencer dentro del plazo.
  bool get warns =>
      status == ExpiryStatus.expired ||
      status == ExpiryStatus.today ||
      status == ExpiryStatus.near;
}

/// Agrupa los lotes con existencia por estado y fecha de vencimiento y suma
/// sus cantidades. Orden: vencidos, hoy, por vencer, más adelante (cada uno
/// por fecha) y, al final, sin fecha. La clasificación es [classifyExpiry],
/// la misma de los avisos (RN-31).
List<ExpiryPortion> expiryPortions({
  required Iterable<({int availableBase, String? expiryDay})> lots,
  required String today,
  required int leadDays,
}) {
  final sums = <(ExpiryStatus, String?), int>{};
  for (final lot in lots) {
    if (lot.availableBase <= 0) continue;
    final status = classifyExpiry(
      expiryDay: lot.expiryDay,
      today: today,
      leadDays: leadDays,
    );
    final key = (status, lot.expiryDay);
    sums[key] = (sums[key] ?? 0) + lot.availableBase;
  }
  const order = [
    ExpiryStatus.expired,
    ExpiryStatus.today,
    ExpiryStatus.near,
    ExpiryStatus.later,
    ExpiryStatus.unknown,
  ];
  final portions = [
    for (final entry in sums.entries)
      ExpiryPortion(
        status: entry.key.$1,
        day: entry.key.$2,
        quantityBase: entry.value,
      ),
  ];
  portions.sort((a, b) {
    final byStatus = order.indexOf(a.status).compareTo(order.indexOf(b.status));
    if (byStatus != 0) return byStatus;
    return (a.day ?? '').compareTo(b.day ?? '');
  });
  return portions;
}

/// «1 L vence el 11/12/2026», «0,5 L vencieron el 07/11/2026», «2 L vencen
/// hoy», «3 L sin fecha de vencimiento».
String expiryPortionText(ExpiryPortion p, String unit) {
  final q = formatQuantity(p.quantityBase, unit);
  final one = _singular(p.quantityBase);
  final day = p.day == null ? '' : formatDate(p.day);
  return switch (p.status) {
    ExpiryStatus.expired => '$q ${one ? 'venció' : 'vencieron'} el $day',
    ExpiryStatus.today => '$q ${one ? 'vence' : 'vencen'} hoy',
    ExpiryStatus.near ||
    ExpiryStatus.later => '$q ${one ? 'vence' : 'vencen'} el $day',
    ExpiryStatus.unknown => '$q sin fecha de vencimiento',
  };
}

/// Etiqueta de la tarjeta de un producto en la lista de Almacén para los
/// lotes por vencer: la cantidad y cuándo vence la más próxima, no «Por
/// vencer» a secas (que se leía como si venciera todo el producto).
String nearExpiryBadge(Iterable<LotExpiryAlert> near, String unit) {
  final alerts = near.where((a) => a.days != null).toList();
  if (alerts.isEmpty) return 'Por vencer';
  final first = alerts.map((a) => a.days!).reduce((a, b) => a < b ? a : b);
  final total = alerts.fold(0, (sum, a) => sum + a.lot.remainingBase);
  final firstBase = alerts
      .where((a) => a.days == first)
      .fold(0, (sum, a) => sum + a.lot.remainingBase);
  final days = first == 1 ? '1 día' : '$first días';
  if (firstBase == total) {
    return '${formatQuantity(total, unit)} '
        '${_singular(total) ? 'vence' : 'vencen'} en $days';
  }
  return '${formatQuantity(total, unit)} por vencer, desde $days';
}

/// Etiqueta de la tarjeta para lo que vence hoy, con la cantidad.
String todayExpiryBadge(Iterable<LotExpiryAlert> today, String unit) {
  final total = today.fold(0, (sum, a) => sum + a.lot.remainingBase);
  return '${formatQuantity(total, unit)} '
      '${_singular(total) ? 'vence' : 'vencen'} hoy';
}

/// Costo de un lote por unidad mayor: «45,00 Bs por L».
String lotCostText(int unitCostMinor, String unit) =>
    '${formatBob(unitCostMinor).replaceAll(' ', ' ').trim()} por $unit';

/// Referencia visual corta para entradas que a la vista serían iguales:
/// misma persona y mismo día de compra. Devuelve, por posición en [lots],
/// «entrada i de n» o nulo si no hace falta. El orden es el de [lots] (el
/// del repositorio: fecha de compra y, dentro de ella, orden de registro),
/// así que la referencia es estable mientras las entradas tengan existencia.
List<String?> lotReferences(List<({String person, String acquiredDay})> lots) {
  final totals = <(String, String), int>{};
  for (final lot in lots) {
    final key = (lot.person, lot.acquiredDay);
    totals[key] = (totals[key] ?? 0) + 1;
  }
  final seen = <(String, String), int>{};
  final references = <String?>[];
  for (final lot in lots) {
    final key = (lot.person, lot.acquiredDay);
    final total = totals[key]!;
    if (total < 2) {
      references.add(null);
      continue;
    }
    final position = (seen[key] ?? 0) + 1;
    seen[key] = position;
    references.add('entrada $position de $total');
  }
  return references;
}

/// Línea de vencimiento con icono: el texto dice el estado, el color lo
/// refuerza.
class ExpiryLine extends StatelessWidget {
  const ExpiryLine({
    super.key,
    required this.status,
    required this.text,
    this.onDark = false,
    this.style,
  });

  final ExpiryStatus status;
  final String text;

  /// Sobre la cabecera oscura del producto.
  final bool onDark;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final (icon, light, dark) = switch (status) {
      ExpiryStatus.expired => (
        Icons.error_outline,
        AgroColors.danger,
        const Color(0xFFFFB4AB),
      ),
      ExpiryStatus.today || ExpiryStatus.near => (
        Icons.warning_amber_rounded,
        AgroColors.caution,
        AgroColors.warnBg,
      ),
      ExpiryStatus.later => (
        Icons.event_available_outlined,
        AgroColors.muted,
        AgroColors.onInkMuted,
      ),
      ExpiryStatus.unknown => (
        Icons.help_outline,
        AgroColors.muted,
        AgroColors.onInkMuted,
      ),
    };
    final color = onDark ? dark : light;
    final warns =
        status == ExpiryStatus.expired ||
        status == ExpiryStatus.today ||
        status == ExpiryStatus.near;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style:
                style ??
                TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: warns ? FontWeight.w700 : FontWeight.w400,
                  color: onDark
                      ? (warns ? color : AgroColors.onInk)
                      : (warns ? color : AgroColors.muted),
                ),
          ),
        ),
      ],
    );
  }
}

/// Un lote con existencia, como fila legible: quién y cuánto; cuándo se
/// compró; cuándo vence; y, en pequeño, costo, proveedor, campaña y el
/// número del fabricante si existe. Sin identificador interno.
class LotCard extends StatelessWidget {
  const LotCard({
    super.key,
    required this.person,
    required this.quantity,
    required this.purchaseDay,
    required this.expiryStatus,
    required this.expiryText,
    required this.details,
    this.manufacturerLot,
    this.reference,
    this.fromTransfer = false,
  });

  final String person;
  final String quantity;

  /// Fecha de compra ya formateada (dd/mm/aaaa).
  final String purchaseDay;
  final ExpiryStatus expiryStatus;
  final String expiryText;

  /// Datos secundarios (costo, proveedor, campaña).
  final List<String> details;
  final String? manufacturerLot;

  /// «entrada 1 de 2», sólo si hace falta distinguir.
  final String? reference;

  /// El lote llegó por un pase de otra persona (conserva la fecha de compra
  /// del lote de origen).
  final bool fromTransfer;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: AgroColors.canvas,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(person, style: AgroText.question)),
            const SizedBox(width: 8),
            Text(quantity, style: AgroText.amount),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          [
            'Comprado el $purchaseDay',
            if (fromTransfer) 'recibido por pase',
            ?reference,
          ].join(' · '),
          style: const TextStyle(
            fontSize: 14,
            height: 20 / 14,
            color: AgroColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        ExpiryLine(status: expiryStatus, text: expiryText),
        if (details.isNotEmpty || manufacturerLot != null)
          const SizedBox(height: 6),
        for (final line in details) Text(line, style: AgroText.detail),
        if (manufacturerLot != null)
          Text(
            '$manufacturerLotLabel: $manufacturerLot',
            style: AgroText.detail,
          ),
      ],
    ),
  );
}
