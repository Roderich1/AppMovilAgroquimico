import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/inventory_alerts.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';

/// Vista de avisos de existencias y vencimiento (F04-AV, MOB #170; CU-22).
///
/// Sólo lee: se calcula al abrir, sin red, con los datos de este teléfono.
/// No cambia existencias, no bloquea operaciones, no envía notificaciones
/// del sistema y no publica nada. Tocar un aviso abre el producto, sin
/// iniciar ninguna operación.
class InventoryAlertsScreen extends ConsumerStatefulWidget {
  const InventoryAlertsScreen({super.key, this.now});

  /// Reloj inyectable para las pruebas; por defecto, el del teléfono.
  final DateTime Function()? now;

  @override
  ConsumerState<InventoryAlertsScreen> createState() =>
      _InventoryAlertsScreenState();
}

class _InventoryAlertsScreenState extends ConsumerState<InventoryAlertsScreen> {
  late Future<InventoryAlerts> future;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<InventoryAlerts> _load() => ref
      .read(repositoryProvider)
      .inventoryAlerts(now: widget.now?.call() ?? DateTime.now());

  /// Abre el producto sin iniciar ninguna operación y, al volver,
  /// recalcula: el nivel o el plazo pudieron cambiar allí.
  Future<void> _openProduct(int productId) async {
    await context.push('/inventario/$productId');
    if (mounted) _refresh();
  }

  void _refresh() {
    final next = _load();
    setState(() {
      future = next;
    });
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Avisos de inventario',
    subtitle: inventoryAlertsSubtitle,
    action: IconButton.filledTonal(
      tooltip: 'Volver a calcular',
      onPressed: _refresh,
      icon: const Icon(Icons.refresh),
    ),
    child: FutureBuilder<InventoryAlerts>(
      future: future,
      builder: (context, snapshot) {
        // CU-22 E1: si no se pudo leer todo, no se muestra una lista que
        // parezca completa.
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            message:
                'No se pudieron calcular los avisos: '
                '${friendlyError(snapshot.error!)} No se muestra una lista '
                'incompleta.',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _AlertsBody(alerts: snapshot.data!, onOpenProduct: _openProduct);
      },
    ),
  );
}

/// Subtítulo de la vista: qué son los avisos y qué no hacen.
const inventoryAlertsSubtitle =
    'Se calculan en este teléfono, también sin internet. No cambian sus '
    'existencias ni impiden registrar operaciones.';

String _daysText(int days) => days == 1 ? '1 día' : '$days días';

/// Texto del vencimiento de un aviso: vencido, vence hoy o vence en N días.
String expiryPhrase(LotExpiryAlert alert) {
  final day = alert.lot.expiryDay;
  if (day == null) return 'Sin fecha de vencimiento registrada';
  final days = alert.days!;
  return switch (alert.status) {
    ExpiryStatus.expired =>
      'Venció el ${displayDay(day)}, hace ${_daysText(days)}',
    ExpiryStatus.today => 'Vence hoy, ${displayDay(day)}',
    _ => 'Vence el ${displayDay(day)}, en ${_daysText(days)}',
  };
}

String _lotTitle(AlertLot lot) =>
    '${lot.productName} · '
    '${lot.lotNumber == null ? 'sin número de lote' : 'lote ${lot.lotNumber}'}';

class _AlertsBody extends StatelessWidget {
  const _AlertsBody({required this.alerts, required this.onOpenProduct});
  final InventoryAlerts alerts;
  final void Function(int productId) onOpenProduct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = alerts;
    final nothing =
        a.expired.isEmpty &&
        a.dueToday.isEmpty &&
        a.near.isEmpty &&
        a.lowStock.isEmpty &&
        a.unknownDate.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (a.clockLooksBehind)
          Card(
            key: const Key('alerts-clock-warning'),
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Revise la fecha del teléfono'),
              subtitle: Text(
                'El teléfono marca el ${displayDay(a.today)}, antes del último '
                'movimiento registrado (${displayDay(a.lastMovementDay!)}). '
                'Los vencimientos se calculan con la fecha del teléfono.',
              ),
            ),
          ),
        if (nothing)
          const EmptyState(
            key: Key('alerts-empty'),
            icon: Icons.check_circle_outline,
            message: 'No hay avisos de inventario.',
          ),
        _Section(
          keyName: 'alerts-expired',
          title: 'Vencidos',
          help: 'Lotes con producto cuya fecha de vencimiento ya pasó.',
          children: [
            for (final alert in a.expired)
              _LotTile(
                alert: alert,
                shared: a.shared,
                urgent: true,
                onOpen: onOpenProduct,
              ),
          ],
        ),
        // Destacado y aparte de los próximos: hoy todavía no está vencido,
        // mañana sí (decisión del autor del 2026-11-01).
        _Section(
          keyName: 'alerts-today',
          title: 'Vence hoy',
          help:
              'Vencen hoy, ${displayDay(a.today)}, según la fecha del '
              'teléfono. Mañana pasan a vencidos.',
          highlight: true,
          children: [
            for (final alert in a.dueToday)
              _LotTile(
                alert: alert,
                shared: a.shared,
                urgent: true,
                onOpen: onOpenProduct,
              ),
          ],
        ),
        _Section(
          keyName: 'alerts-near',
          title: 'Próximos a vencer',
          help:
              'Vencen dentro del plazo de aviso de cada producto. El plazo '
              'inicial es de ${_daysText(a.defaultLeadDays)}; puede '
              'cambiarlo en el detalle de cada producto.',
          children: [
            for (final alert in a.near)
              _LotTile(alert: alert, shared: a.shared, onOpen: onOpenProduct),
          ],
        ),
        // Total de la instalación y cada responsable, por separado: el mismo
        // nivel mínimo del producto se compara con los dos.
        _Section(
          keyName: 'alerts-low',
          title: a.shared
              ? 'Existencia baja en toda la instalación'
              : 'Existencia baja',
          help: 'Lo que queda en total es igual o menor al nivel mínimo.',
          children: [
            for (final alert in a.lowStock)
              if (alert.line.isTotal)
                _LowStockTile(
                  alert: alert,
                  shared: a.shared,
                  onOpen: onOpenProduct,
                ),
          ],
        ),
        if (a.shared)
          _Section(
            keyName: 'alerts-low-person',
            title: 'Existencia baja por responsable',
            help:
                'Lo que tiene cada responsable es igual o menor al nivel '
                'mínimo. Puede haber producto en otras manos: se indica el '
                'total de la instalación.',
            children: [
              for (final alert in a.lowStock)
                if (!alert.line.isTotal)
                  _LowStockTile(
                    alert: alert,
                    shared: a.shared,
                    onOpen: onOpenProduct,
                  ),
            ],
          ),
        _Section(
          keyName: 'alerts-unknown',
          title: 'Sin fecha de vencimiento registrada',
          help:
              'No se sabe si están vigentes o vencidos. Puede registrar la '
              'fecha en Compras, en el detalle de la compra de ese lote.',
          children: [
            for (final alert in a.unknownDate)
              _LotTile(alert: alert, shared: a.shared, onOpen: onOpenProduct),
          ],
        ),
        if (a.productsWithoutLevel.isNotEmpty)
          Padding(
            key: const Key('alerts-without-level'),
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              a.productsWithoutLevel.length == 1
                  ? '${a.productsWithoutLevel.single.productName} no tiene '
                        'nivel mínimo: no se avisa cuando queda poco. Puede '
                        'definirlo en el detalle del producto.'
                  : '${a.productsWithoutLevel.length} productos no tienen '
                        'nivel mínimo: no se avisa cuando queda poco. Puede '
                        'definirlo en el detalle de cada producto.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.keyName,
    required this.title,
    required this.help,
    required this.children,
    this.highlight = false,
  });
  final String keyName;
  final String title;
  final String help;
  final List<Widget> children;

  /// Tarjeta en ámbar, de advertencia: distinta de los próximos (sin color)
  /// y de los vencidos (en rojo).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      key: Key(keyName),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title (${children.length})',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(help, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Card(
            color: highlight
                ? (theme.brightness == Brightness.dark
                      ? Colors.amber.shade900
                      : Colors.amber.shade100)
                : null,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _LotTile extends StatelessWidget {
  const _LotTile({
    required this.alert,
    required this.shared,
    required this.onOpen,
    this.urgent = false,
  });
  final LotExpiryAlert alert;
  final bool shared;
  final bool urgent;
  final void Function(int productId) onOpen;

  @override
  Widget build(BuildContext context) {
    final lot = alert.lot;
    final lead = alert.status == ExpiryStatus.near
        ? ' · Aviso: ${leadDaysText(lot.leadDays)}'
              '${lot.leadDaysIsDefault ? ' (valor inicial)' : ''}'
        : '';
    return ListTile(
      key: Key('alert-lot-${lot.lotId}'),
      leading: Icon(switch (alert.status) {
        ExpiryStatus.expired => Icons.error_outline,
        ExpiryStatus.today => Icons.warning_amber_rounded,
        ExpiryStatus.near => Icons.event_outlined,
        _ => Icons.help_outline,
      }, color: urgent ? Theme.of(context).colorScheme.error : null),
      title: Text(_lotTitle(lot)),
      subtitle: Text(
        '${expiryPhrase(alert)} · Quedan '
        '${formatQuantity(lot.remainingBase, lot.unit)}'
        '${shared ? ' · ${lot.ownerName}' : ''}$lead',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => onOpen(lot.productId),
    );
  }
}

class _LowStockTile extends StatelessWidget {
  const _LowStockTile({
    required this.alert,
    required this.shared,
    required this.onOpen,
  });
  final LowStockAlert alert;
  final bool shared;
  final void Function(int productId) onOpen;

  @override
  Widget build(BuildContext context) {
    final line = alert.line;
    final min = formatQuantity(alert.minStockBase, line.unit);
    final total = formatQuantity(alert.installationNetBase, line.unit);
    final String title;
    final String subtitle;
    if (line.isTotal) {
      title = shared
          ? '${line.productName} · Total de la instalación'
          : line.productName;
      subtitle = line.netBase <= 0
          ? (shared
                ? 'No queda en toda la instalación; nivel mínimo $min'
                : 'No queda; nivel mínimo $min')
          : 'Quedan $total${shared ? ' en toda la instalación' : ''}; '
                'nivel mínimo $min';
    } else {
      title = '${line.productName} · ${line.personName} (responsable)';
      final own = line.netBase <= 0
          ? '${line.personName} no tiene existencias propias'
          : '${line.personName} tiene '
                '${formatQuantity(line.netBase, line.unit)}';
      subtitle =
          '$own; nivel mínimo $min. En toda la instalación: '
          '${alert.installationNetBase <= 0 ? 'no queda' : total}';
    }
    return ListTile(
      key: Key('alert-low-${line.productId}-${line.personId ?? 'total'}'),
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => onOpen(line.productId),
    );
  }
}

/// Resumen corto para la entrada del inventario.
String inventoryAlertsSummary(InventoryAlerts alerts) {
  final lowTotal = alerts.lowStock.where((a) => a.line.isTotal).length;
  final lowPerson = alerts.lowStock.length - lowTotal;
  final parts = [
    if (alerts.expired.isNotEmpty)
      '${alerts.expired.length} '
          '${alerts.expired.length == 1 ? 'vencido' : 'vencidos'}',
    if (alerts.dueToday.isNotEmpty)
      '${alerts.dueToday.length} '
          '${alerts.dueToday.length == 1 ? 'vence' : 'vencen'} hoy',
    if (alerts.near.isNotEmpty) '${alerts.near.length} por vencer',
    // Total y responsables por separado (decisión del 2026-11-01).
    if (lowTotal > 0)
      '$lowTotal ${lowTotal == 1 ? 'bajo' : 'bajos'} en el total',
    if (lowPerson > 0)
      '$lowPerson ${lowPerson == 1 ? 'bajo' : 'bajos'} por responsable',
    if (alerts.unknownDate.isNotEmpty)
      '${alerts.unknownDate.length} sin fecha registrada',
  ];
  return parts.isEmpty ? 'Sin avisos' : parts.join(' · ');
}
