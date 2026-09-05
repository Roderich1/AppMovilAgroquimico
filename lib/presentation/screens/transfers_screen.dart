import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';

class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key});
  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> {
  late Future<List<Map<String, Object?>>> future;
  @override
  void initState() {
    super.initState();
    future = ref.read(repositoryProvider).transfers();
  }

  void refresh() {
    final next = ref.read(repositoryProvider).transfers();
    setState(() => future = next);
  }

  Future<void> reverse(Map<String, Object?> row) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: '¿Revertir esta transferencia?',
      detail:
          '${row['from_person_name']} → ${row['to_person_name']}\n'
          '${row['products_summary']}\n'
          'Costo ${formatBob(row['total_cost_bob_minor']! as int)}\n\n'
          'El stock volverá a la persona de origen. Esta acción no se puede '
          'deshacer.',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(repositoryProvider).reverseTransfer(row['id']! as int);
      if (mounted) refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Transferencias',
    subtitle: 'Operaciones multiproducto con trazabilidad FIFO.',
    action: FilledButton.icon(
      onPressed: () async {
        final saved = await context.push<bool>('/transferencias/nueva');
        if (saved == true && mounted) refresh();
      },
      icon: const Icon(Icons.add),
      label: const Text('Nueva'),
    ),
    child: FutureBuilder<List<Map<String, Object?>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.isEmpty)
          return const EmptyState(
            icon: Icons.swap_horiz,
            message: 'No hay transferencias.',
          );
        return Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: snapshot.data!.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = snapshot.data![index];
              return ExpansionTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text(
                  '${row['from_person_name']} → ${row['to_person_name']}',
                ),
                subtitle: Text(row['products_summary'] as String),
                trailing: row['status'] == 'CONFIRMED'
                    ? IconButton(
                        tooltip: 'Revertir',
                        onPressed: () => reverse(row),
                        icon: const Icon(Icons.undo),
                      )
                    : const Text('Revertida'),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${row['item_count']} producto(s) · ${row['lot_count']} lote(s) · costo ${formatBob(row['total_cost_bob_minor'] as int)}',
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    ),
  );
}
