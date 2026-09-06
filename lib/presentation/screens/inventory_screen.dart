import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  late Future<List<Map<String, Object?>>> future;
  String query = '';
  @override
  void initState() {
    super.initState();
    future = ref.read(repositoryProvider).inventorySummary();
  }

  void refresh() {
    final next = ref.read(repositoryProvider).inventorySummary();
    setState(() {
      future = next;
    });
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
        TextField(
          onChanged: (value) =>
              setState(() => query = value.trim().toLowerCase()),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Buscar producto',
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, Object?>>>(
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
                .where((r) => matchesSearch(r['product_name'] as String, query))
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
                        row['product_name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Físico ${formatQuantity(row['available_base'] as int, row['unit'] as String)} · comprometido ${formatQuantity(row['committed_base'] as int, row['unit'] as String)}',
                      ),
                      trailing: Text(
                        formatQuantity(
                          row['projected_base'] as int,
                          row['unit'] as String,
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: (row['projected_base'] as int) < 0
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                      ),
                      onTap: () =>
                          context.push('/inventario/${row['product_id']}'),
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
