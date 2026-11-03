import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../data/typed_reads.dart';
import '../../domain/inventory_alerts.dart';
import '../../domain/money.dart';
import '../../domain/read_models.dart';
import '../widgets/common.dart';
import 'inventory_alerts_screen.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  late Future<List<InventoryLineRead>> future;

  /// Resumen de avisos (F04-AV, CU-22: «el inventario indica que hay
  /// avisos»). Se calcula al abrir y al refrescar; sólo lee.
  late Future<InventoryAlerts> alerts;
  String query = '';
  @override
  void initState() {
    super.initState();
    future = ref.read(repositoryProvider).inventorySummaryTyped();
    alerts = ref.read(repositoryProvider).inventoryAlerts();
  }

  void refresh() {
    final next = ref.read(repositoryProvider).inventorySummaryTyped();
    final nextAlerts = ref.read(repositoryProvider).inventoryAlerts();
    setState(() {
      future = next;
      alerts = nextAlerts;
    });
  }

  /// F12-EST-07-MOB (#164): la estimación del consumo, sólo lectura.
  Future<void> _openEstimation() async {
    await context.push('/inventario/estimacion');
    if (mounted) refresh();
  }

  Future<void> _openAlerts() async {
    await context.push('/inventario/avisos');
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Inventario',
    subtitle: 'Stock físico global, compromisos y saldo proyectado.',
    action: IconButton.filledTonal(
      onPressed: refresh,
      icon: const Icon(Icons.refresh),
    ),
    child: Column(
      children: [
        FutureBuilder<InventoryAlerts>(
          future: alerts,
          builder: (context, snapshot) => Card(
            key: const Key('inventory-alerts-entry'),
            child: ListTile(
              leading: const Icon(Icons.warning_amber_outlined),
              title: const Text('Avisos de inventario'),
              subtitle: Text(
                snapshot.hasError
                    ? 'No se pudieron calcular. Ábralos para ver el motivo.'
                    : snapshot.hasData
                    ? inventoryAlertsSummary(snapshot.data!)
                    : 'Calculando…',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openAlerts,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          key: const Key('inventory-estimation-entry'),
          child: ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text('Estimación del consumo'),
            subtitle: const Text(
              'Referencia para la próxima campaña; no cambia el inventario.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openEstimation,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: (value) =>
              setState(() => query = value.trim().toLowerCase()),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Buscar producto',
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<InventoryLineRead>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return EmptyState(
                icon: Icons.error_outline,
                message: friendlyError(snapshot.error!),
              );
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final rows = snapshot.data!
                .where((r) => matchesSearch(r.productName, query))
                .toList();
            if (rows.isEmpty)
              return const EmptyState(
                icon: Icons.inventory_2_outlined,
                message: 'No hay productos para mostrar.',
              );
            return Card(
              child: Column(
                children: [
                  for (final row in rows)
                    ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(
                        row.productName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Físico ${formatQuantity(row.availableBase, row.unit)} · comprometido ${formatQuantity(row.committedBase, row.unit)}',
                      ),
                      trailing: Text(
                        formatQuantity(row.projectedBase, row.unit),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: row.projectedBase < 0
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                      onTap: () => context.push('/inventario/${row.productId}'),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    ),
  );
}
