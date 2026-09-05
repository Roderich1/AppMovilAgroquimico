import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../widgets/common.dart';

class ApplicationsScreen extends ConsumerStatefulWidget {
  const ApplicationsScreen({super.key});
  @override
  ConsumerState<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends ConsumerState<ApplicationsScreen> {
  late Future<List<Map<String, Object?>>> future;
  String query = '';
  int? campaignFilter;
  @override
  void initState() {
    super.initState();
    future = ref.read(repositoryProvider).applications(limit: 200);
  }

  void refresh() {
    final next = ref.read(repositoryProvider).applications(limit: 200);
    setState(() => future = next);
  }

  Future<void> add() async {
    final active = await ref.read(repositoryProvider).activeCampaign();
    if (!mounted) return;
    if (active == null) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Falta una campaña activa'),
          content: const Text(
            'Active una campaña antes de registrar aplicaciones.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Ir a campañas'),
            ),
          ],
        ),
      );
      if (go == true && mounted) context.go('/catalogos');
      return;
    }
    final saved = await context.push<bool>('/aplicaciones/nueva');
    if (saved == true && mounted) {
      refresh();
      showSuccess(context, 'Aplicación multiproducto confirmada.');
    }
  }

  Future<void> reverse(Map<String, Object?> row) async {
    final confirmed = await confirmDestructiveAction(
      context,
      title: '¿Revertir esta aplicación?',
      detail:
          '${row['person_name']} · ${row['farm_name']}\n'
          '${row['campaign_name']}\n'
          'Costo ${formatBob(row['total_cost_bob_minor']! as int)}\n\n'
          'Se devolverá el producto consumido al inventario y se anulará el '
          'cargo correspondiente. Esta acción no se puede deshacer.',
    );
    if (!confirmed || !mounted) return;
    try {
      await ref
          .read(repositoryProvider)
          .reverseApplication(
            row['id']! as int,
            reason: 'Reversión solicitada por usuario',
          );
      if (mounted) refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Aplicaciones',
    subtitle: 'Eventos de fumigación con uno o varios productos.',
    action: FilledButton.icon(
      onPressed: add,
      icon: const Icon(Icons.add),
      label: const Text('Registrar'),
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
        final campaigns = {
          for (final row in snapshot.data!) row['campaign_id'] as int: row,
        };
        final rows = snapshot.data!
            .where(
              (row) =>
                  (campaignFilter == null ||
                      row['campaign_id'] == campaignFilter) &&
                  '$row'.toLowerCase().contains(query),
            )
            .toList();
        return Column(
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final filters = [
                  DropdownButtonFormField<int?>(
                    initialValue: campaignFilter,
                    decoration: const InputDecoration(labelText: 'Campaña'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todas')),
                      for (final row in campaigns.values)
                        DropdownMenuItem(
                          value: row['campaign_id'] as int,
                          child: Text(row['campaign_name'] as String),
                        ),
                    ],
                    onChanged: (v) => setState(() => campaignFilter = v),
                  ),
                  TextField(
                    onChanged: (v) =>
                        setState(() => query = v.trim().toLowerCase()),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Buscar persona o chaco',
                    ),
                  ),
                ];
                return c.maxWidth >= 600
                    ? Row(
                        children: [
                          Expanded(child: filters[0]),
                          const SizedBox(width: 8),
                          Expanded(child: filters[1]),
                        ],
                      )
                    : Column(
                        children: [
                          filters[0],
                          const SizedBox(height: 8),
                          filters[1],
                        ],
                      );
              },
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const EmptyState(
                icon: Icons.agriculture_outlined,
                message: 'No hay aplicaciones para mostrar.',
              )
            else
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      leading: const Icon(Icons.agriculture_outlined),
                      title: Text(
                        '${row['person_name']} · ${row['farm_name']}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${row['campaign_name']} · ${row['item_count']} producto(s)\n${row['items_summary']}',
                      ),
                      trailing: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(formatBob(row['total_cost_bob_minor'] as int)),
                          if (row['status'] != 'REVERSED')
                            IconButton(
                              tooltip: 'Revertir',
                              onPressed: () => reverse(row),
                              icon: const Icon(Icons.undo),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    ),
  );
}
