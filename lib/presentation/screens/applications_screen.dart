import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/auth/local_owner_credential.dart'
    show AuthorizationPurpose;
import '../widgets/owner_reversal_flow.dart';

import '../../app.dart';
import '../../domain/money.dart';
import '../../domain/operation_mode.dart';
import '../../operation_mode_controller.dart';
import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';
import '../widgets/common.dart';
import '../widgets/rdm_a_list.dart';

class ApplicationsScreen extends ConsumerStatefulWidget {
  const ApplicationsScreen({super.key});
  @override
  ConsumerState<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

typedef _ApplicationsView = ({
  List<Map<String, Object?>> rows,
  OperationMode mode,
  int? ownerPersonId,
});

class _ApplicationsScreenState extends ConsumerState<ApplicationsScreen> {
  late Future<_ApplicationsView> future;
  String query = '';
  int? campaignFilter;
  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<_ApplicationsView> _load() async {
    final repo = ref.read(repositoryProvider);
    final (rows, operating) = await (
      repo.applications(limit: 200),
      repo.operatingContext(),
    ).wait;
    return (
      rows: rows,
      mode: operating.mode,
      ownerPersonId: operating.ownerPersonId,
    );
  }

  void refresh() {
    final next = _load();
    setState(() {
      future = next;
    });
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
      if (go == true && mounted) unawaited(context.push('/campanas'));
      return;
    }
    final saved = await context.push<bool>('/aplicaciones/nueva');
    if (saved == true && mounted) {
      refresh();
      showSuccess(context, 'Aplicación registrada.');
    }
  }

  Future<void> reverse(
    Map<String, Object?> row, {
    required bool personal,
    required bool hideOwner,
  }) async {
    final id = row['id']! as int;
    // RF-13: motivo y PIN del titular; el actor sale de la autorización.
    final approval = await requestOwnerApproval(
      context,
      ref,
      purpose: AuthorizationPurpose.reverseApplication,
      subjectRef: 'application:$id',
      title: '¿Revertir esta aplicación?',
      effects:
          '${hideOwner ? '${row['farm_name']}' : '${row['person_name']} · ${row['farm_name']}'}\n'
          '${row['campaign_name']}\n'
          'Costo ${formatBob(row['total_cost_bob_minor']! as int)}\n\n'
          'Se devolverá el producto consumido al inventario y '
          '${personal ? 'se restará de los costos del chaco' : 'se anulará el cargo correspondiente'}. '
          'Esta acción no se puede deshacer. '
          '${personal ? 'La aplicación original conserva su fecha.' : 'La aplicación original conserva su responsable y su fecha.'}',
      confirmLabel: 'Revertir aplicación',
      revalidate: reversalStillPending(ref, 'applications', id),
    );
    if (approval == null || !mounted) return;
    try {
      await ref
          .read(repositoryProvider)
          .reverseApplication(
            id,
            reason: approval.reason,
            authorization: approval.authorization,
          );
      if (mounted) refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liveMode = ref.watch(operationModeProvider);
    return RdmAListPage(
      title: 'Aplicaciones',
      // Desde B1 no hay «+ Registrar» flotante aquí: el botón dice qué registra.
      action: RdmARegisterButton(
        key: const Key('applications-register'),
        label: 'Registrar aplicación',
        onPressed: add,
      ),
      child: FutureBuilder<_ApplicationsView>(
        future: future,
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
          final loaded = snapshot.data!;
          final personal = (liveMode ?? loaded.mode) == OperationMode.personal;
          final ownerPersonId = loaded.ownerPersonId;
          bool isHiddenOwner(Map<String, Object?> row) =>
              personal &&
              ownerPersonId != null &&
              row['person_id'] == ownerPersonId;
          final campaigns = {
            for (final row in loaded.rows) row['campaign_id'] as int: row,
          };
          final rows = loaded.rows.where((row) {
            if (campaignFilter != null &&
                row['campaign_id'] != campaignFilter) {
              return false;
            }
            if (query.isEmpty) return true;
            final hide = isHiddenOwner(row);
            final searchable =
                '${row['farm_name']} ${row['campaign_name']} '
                '${row['items_summary'] ?? ''} '
                '${hide ? '' : row['person_name']}';
            return matchesSearch(searchable, query);
          }).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final filters = [
                    DropdownButtonFormField<int?>(
                      initialValue: campaignFilter,
                      decoration: const InputDecoration(labelText: 'Campaña'),
                      items: [
                        const DropdownMenuItem(child: Text('Todas')),
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
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText: personal
                            ? 'Buscar chaco o producto'
                            : 'Buscar persona o chaco',
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
              const SizedBox(height: 16),
              if (rows.isEmpty)
                const RdmAEmpty(
                  icon: Icons.spa_outlined,
                  message: 'No hay aplicaciones para mostrar.',
                )
              else
                AgroGroup(
                  children: [
                    for (final row in rows)
                      _ApplicationRow(
                        key: Key('application-row-${row['id']}'),
                        row: row,
                        hideOwner: isHiddenOwner(row),
                        onReverse: () => reverse(
                          row,
                          personal: personal,
                          hideOwner: isHiddenOwner(row),
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Una aplicación de la lista: persona y chaco, campaña y productos, costo
/// y, si sigue vigente, «Revertir». Una revertida lo dice con su etiqueta y
/// quién la autorizó; su costo queda tachado (UIBUG-010: la falta del botón
/// no basta para saber que está revertida).
class _ApplicationRow extends StatelessWidget {
  const _ApplicationRow({
    super.key,
    required this.row,
    required this.hideOwner,
    required this.onReverse,
  });

  final Map<String, Object?> row;
  final bool hideOwner;
  final VoidCallback onReverse;

  @override
  Widget build(BuildContext context) {
    final reversed = row['status'] == 'REVERSED';
    final cost = formatBob(row['total_cost_bob_minor']! as int);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AmountAside(
            amount: cost,
            amountStyle: reversed
                ? AgroText.amount.copyWith(
                    color: AgroColors.muted,
                    decoration: TextDecoration.lineThrough,
                  )
                : AgroText.amount,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hideOwner
                      ? '${row['farm_name']}'
                      : '${row['person_name']} · ${row['farm_name']}',
                  style: AgroText.value,
                ),
                Text(
                  '${row['campaign_name']} · '
                  '${rdmAProducts(row['item_count']! as int)}',
                  style: AgroText.detail,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatItemsSummary(row['items_summary']),
            style: AgroText.detail.copyWith(color: AgroColors.ink),
          ),
          if (reversed) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusBadge(
                label: operationStatusLabel(row['status']),
                tone: BadgeTone.neutral,
              ),
            ),
            // RF-13 §1.3: quién autorizó la reversión, o «Actor no
            // registrado» si es anterior a la auditoría.
            ReversalActorText(
              operationType: 'APPLICATION',
              operationId: row['id']! as int,
            ),
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: 'Revertir',
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AgroColors.link,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.only(right: 8),
                    textStyle: const TextStyle(
                      fontFamily: AgroFonts.body,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: onReverse,
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Revertir'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
