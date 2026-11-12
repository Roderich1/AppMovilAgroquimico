import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../widgets/campaign_actions.dart';
import '../widgets/catalog_dialogs.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/rdm_c_page.dart';

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
  Widget _menu(Map<String, Object?> row, {Color color = AgroColors.ink}) =>
      PopupMenuButton<String>(
        tooltip: 'Opciones de ${row['name']}',
        icon: Icon(Icons.more_vert, color: color),
        onSelected: (value) => _onMenu(value, row),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Editar nombre')),
          if (row['status'] == 'PLANNED')
            const PopupMenuItem(value: 'activate', child: Text('Activar')),
          if (row['status'] == 'ACTIVE')
            const PopupMenuItem(value: 'close', child: Text('Cerrar')),
        ],
      );

  /// Cifra pequeña de la tarjeta oscura («Empezó», «Fin previsto»).
  Widget _dateBox(String label, String value) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
    decoration: BoxDecoration(
      color: AgroColors.inkSoft,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AgroText.label.copyWith(color: AgroColors.onInkMuted),
        ),
        Text(value, style: AgroText.value.copyWith(color: Colors.white)),
      ],
    ),
  );

  /// Tarjeta oscura de la campaña actual (lámina «Campañas»).
  Widget _current(Map<String, Object?>? row) => Material(
    key: const Key('campaigns-current'),
    color: AgroColors.ink,
    borderRadius: BorderRadius.circular(28),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 20),
      child: row == null
          ? Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const StatusBadge(
                    label: 'Sin campaña activa',
                    tone: BadgeTone.review,
                  ),
                  const SizedBox(height: 10),
                  // El efecto, no una instrucción: sin campaña activa no se
                  // registran operaciones nuevas.
                  Text(
                    'No se pueden registrar compras, aplicaciones ni planes '
                    'nuevos.',
                    style: AgroText.value.copyWith(color: Colors.white),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StatusBadge(
                          label: 'Campaña actual',
                          tone: BadgeTone.ok,
                        ),
                      ),
                    ),
                    _menu(row, color: Colors.white),
                  ],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    row['name'].toString(),
                    style: AgroText.h1.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _dateBox('Empezó', formatDate(row['start_date'])),
                      if (row['end_date'] != null)
                        _dateBox('Fin previsto', formatDate(row['end_date'])),
                    ],
                  ),
                ),
              ],
            ),
    ),
  );

  @override
  Widget build(BuildContext context) => RdmCPage(
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _current(current.isEmpty ? null : current.first),
            const SizedBox(height: 16),
            if (others.isEmpty)
              Text('No hay otras campañas.', style: AgroText.detail)
            else ...[
              const SectionHeader(title: 'Otras campañas'),
              const SizedBox(height: 8),
              AgroGroup(
                children: [
                  for (final row in others)
                    RdmCRow(
                      title: row['name'].toString(),
                      detail: campaignSubtitle(row, all),
                      trailing: _menu(row),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    ),
  );
}
