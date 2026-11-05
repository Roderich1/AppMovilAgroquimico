import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../widgets/campaign_actions.dart';
import '../widgets/catalog_dialogs.dart';
import '../widgets/common.dart';

/// Campañas, con acceso propio desde Operaciones. Arriba la campaña actual
/// (la activa: la que reciben las compras, aplicaciones y planes nuevos) y
/// debajo las demás. Activar, cerrar y crear usan las mismas funciones que
/// la sección Campañas de Catálogos (`campaign_actions.dart`), así que las
/// reglas de cambio y cierre no cambian: «Cerrar y activar» si hay otra
/// activa, cierre con resumen y fin efectivo, y sin reactivar una cerrada.
class CampaignsScreen extends ConsumerStatefulWidget {
  const CampaignsScreen({super.key});

  @override
  ConsumerState<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends ConsumerState<CampaignsScreen> {
  late Future<List<Map<String, Object?>>> data = _load();

  Future<List<Map<String, Object?>>> _load() =>
      ref.read(repositoryProvider).campaigns();

  void _refresh() {
    final next = _load();
    setState(() {
      data = next;
    });
  }

  Future<void> _run(Future<bool> Function() action) async {
    try {
      if (await action() && mounted) _refresh();
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<bool> _rename(Map<String, Object?> row) async {
    final value = await showDialog<String?>(
      context: context,
      builder: (_) => NameDialog(
        title: 'Editar nombre',
        label: 'Nombre',
        initial: row['name']! as String,
      ),
    );
    if (value == null) return false;
    await ref
        .read(repositoryProvider)
        .renameCatalog('campaigns', row['id']! as int, value);
    return true;
  }

  void _onMenu(String action, Map<String, Object?> row) {
    final repo = ref.read(repositoryProvider);
    _run(
      () => switch (action) {
        'activate' => activateCampaignFlow(context, repo, row),
        'close' => closeCampaignFlow(context, repo, row),
        _ => _rename(row),
      },
    );
  }

  /// Menú de una campaña. Sólo se activa una planificada (UIBUG-059) y sólo
  /// se cierra la activa; el repositorio lo exige igual.
  Widget _menu(Map<String, Object?> row) => PopupMenuButton<String>(
    tooltip: 'Opciones de ${row['name']}',
    onSelected: (value) => _onMenu(value, row),
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'edit', child: Text('Editar nombre')),
      if (row['status'] == 'PLANNED')
        const PopupMenuItem(value: 'activate', child: Text('Activar')),
      if (row['status'] == 'ACTIVE')
        const PopupMenuItem(value: 'close', child: Text('Cerrar')),
    ],
  );

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Campañas',
    action: FilledButton.icon(
      key: const Key('campaigns-add'),
      onPressed: () =>
          _run(() => addCampaignFlow(context, ref.read(repositoryProvider))),
      icon: const Icon(Icons.add),
      label: const Text('Agregar campaña'),
    ),
    child: FutureBuilder<List<Map<String, Object?>>>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!;
        final current = all.where((row) => row['status'] == 'ACTIVE');
        final others = all.where((row) => row['status'] != 'ACTIVE').toList();
        final theme = Theme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              key: const Key('campaigns-current'),
              color: theme.colorScheme.primaryContainer,
              child: current.isEmpty
                  ? const ListTile(
                      contentPadding: EdgeInsets.all(16),
                      leading: Icon(Icons.warning_amber_outlined),
                      title: Text(
                        'Sin campaña activa',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      // El efecto, no una instrucción: sin campaña activa no
                      // se registran operaciones nuevas.
                      subtitle: Text(
                        'No se pueden registrar compras, aplicaciones ni '
                        'planes nuevos.',
                      ),
                    )
                  : ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: Text(
                        current.first['name'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        'Actual · desde ${formatDate(current.first['start_date'])}'
                        '${current.first['end_date'] == null ? '' : ' · fin previsto ${formatDate(current.first['end_date'])}'}',
                      ),
                      trailing: _menu(current.first),
                    ),
            ),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionHeading(title: 'Otras campañas'),
              const SizedBox(height: 8),
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: others.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) => ListTile(
                    title: Text(others[index]['name'].toString()),
                    subtitle: Text(campaignSubtitle(others[index], all)),
                    trailing: _menu(others[index]),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}
