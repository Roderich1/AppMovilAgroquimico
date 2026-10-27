import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show repositoryProvider;
import '../../data/agro_repository.dart';
import '../../services/auth/local_owner_credential.dart';
import '../../domain/money.dart' show formatDate;
import '../widgets/common.dart';
import '../widgets/owner_reversal_flow.dart' show lateDraftStillPending;
import 'owner_credential_screen.dart';

/// RF-03 (docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md §2.1 paso 3): si
/// la fecha cae en una campaña cerrada, ofrece «Registrar para revisión» con
/// motivo. Devuelve true si quedó guardado un borrador pendiente.
Future<bool> offerLateRegistration(
  BuildContext context, {
  required Object error,
  required String what,
  required Future<String> Function(String reason) capture,
  String? extraNote,
}) async {
  if (error is! CampaignDateException ||
      error.problem != CampaignDateProblem.closed) {
    return false;
  }
  final reason = await showDialog<String>(
    context: context,
    builder: (context) => _LateReasonDialog(
      message:
          '${error.message}\n\nPuede registrar $what para revisión: queda '
          'pendiente, sin efecto en existencias, costos ni publicaciones, hasta '
          'que el titular la confirme o la rechace con su PIN.'
          '${extraNote == null ? '' : '\n\n$extraNote'}',
    ),
  );
  if (reason == null || !context.mounted) return false;
  await capture(reason);
  if (context.mounted) {
    showSuccess(
      context,
      'Guardada para revisión. Confírmela en «Operaciones tardías».',
    );
  }
  return true;
}

class _LateReasonDialog extends StatefulWidget {
  const _LateReasonDialog({required this.message});

  final String message;

  @override
  State<_LateReasonDialog> createState() => _LateReasonDialogState();
}

class _LateReasonDialogState extends State<_LateReasonDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Fecha de una campaña cerrada'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message, key: const Key('late-explanation')),
          const SizedBox(height: 12),
          TextField(
            key: const Key('late-reason'),
            controller: _reason,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: 'Motivo (obligatorio)',
              errorText: _error,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        key: const Key('late-register'),
        onPressed: () {
          final value = _reason.text.trim();
          if (value.isEmpty) {
            setState(() => _error = 'Indique el motivo.');
            return;
          }
          Navigator.pop(context, value);
        },
        child: const Text('Registrar para revisión'),
      ),
    ],
  );
}

/// Lista de operaciones tardías: el titular confirma o rechaza con su PIN y
/// puede definir un período histórico cuando falta (§2.5).
class LateOperationsScreen extends ConsumerStatefulWidget {
  const LateOperationsScreen({super.key});

  @override
  ConsumerState<LateOperationsScreen> createState() =>
      _LateOperationsScreenState();
}

class _LateOperationsScreenState extends ConsumerState<LateOperationsScreen> {
  late Future<List<Map<String, Object?>>> _drafts;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _drafts = ref.read(repositoryProvider).lateOperationDrafts();
  }

  void _refresh() {
    final next = ref.read(repositoryProvider).lateOperationDrafts();
    setState(() {
      _drafts = next;
    });
  }

  String _kind(Object? kind) => kind == 'PURCHASE' ? 'Compra' : 'Aplicación';

  Future<void> _resolve(
    Map<String, Object?> draft, {
    required bool confirm,
  }) async {
    if (_busy) return;
    final ref_ = draft['draft_ref']! as String;
    final authorization = await requestOwnerAuthorization(
      context,
      ref,
      purpose: confirm
          ? AuthorizationPurpose.confirmLateOperation
          : AuthorizationPurpose.rejectLateOperation,
      subjectRef: 'late:$ref_',
      title: confirm
          ? 'Confirmar operación tardía'
          : 'Rechazar operación tardía',
      effects: confirm
          ? '${_kind(draft['kind'])} del ${formatDate(draft['effective_date'])} '
                'en «${draft['campaign_name']}». Se revalidan la campaña y las '
                'existencias de esa fecha y se aplica una sola vez. Es una '
                'corrección privada: el consolidado del sindicato no cambia.'
          : '${_kind(draft['kind'])} del ${formatDate(draft['effective_date'])}. '
                'Se descarta sin efectos.',
      revalidate: lateDraftStillPending(ref, ref_),
    );
    if (authorization == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      final result = confirm
          ? await repo.confirmLateOperation(ref_, authorization: authorization)
          : await repo.rejectLateOperation(ref_, authorization: authorization);
      if (!mounted) return;
      switch (result.outcome) {
        case LateResolutionOutcome.confirmed:
          showSuccess(context, result.message ?? 'Confirmada.');
        case LateResolutionOutcome.rejected:
          showSuccess(context, 'Rechazada sin efectos.');
        case LateResolutionOutcome.conflict:
          showError(context, result.message ?? 'No se pudo aplicar.');
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
  }

  Future<void> _historicalPeriod() async {
    final name = TextEditingController();
    DateTime? start;
    DateTime? end;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> pick(bool isStart) async {
            final picked = await showDatePicker(
              context: context,
              firstDate: DateTime(2000),
              lastDate: DateTime.now().subtract(const Duration(days: 1)),
              initialDate: DateTime.now().subtract(const Duration(days: 1)),
            );
            if (picked != null)
              setLocal(() => isStart ? start = picked : end = picked);
          }

          return AlertDialog(
            title: const Text('Nuevo período histórico'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Para registrar operaciones de una fecha sin campaña. Se crea '
                  'cerrado, sin solaparse con ninguna campaña, y no cambia la '
                  'campaña activa. Es un período local: nunca se publica al '
                  'sindicato desde él.',
                ),
                TextField(
                  key: const Key('historical-name'),
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                TextButton(
                  onPressed: () => pick(true),
                  child: Text(
                    start == null
                        ? 'Elegir inicio'
                        : 'Inicio: ${formatDate(start!.toIso8601String())}',
                  ),
                ),
                TextButton(
                  onPressed: () => pick(false),
                  child: Text(
                    end == null
                        ? 'Elegir fin'
                        : 'Fin: ${formatDate(end!.toIso8601String())}',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: start == null || end == null
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('Crear período'),
              ),
            ],
          );
        },
      ),
    );
    if (saved != true || !mounted) return;
    try {
      await ref
          .read(repositoryProvider)
          .addHistoricalCampaign(name: name.text, start: start!, end: end!);
      if (mounted) showSuccess(context, 'Período histórico creado.');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      name.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Operaciones tardías')),
    floatingActionButton: FloatingActionButton.extended(
      key: const Key('late-historical-period'),
      onPressed: _historicalPeriod,
      icon: const Icon(Icons.history),
      label: const Text('Período histórico'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _drafts,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.error_outline,
            message: friendlyError(snapshot.error!),
          );
        }
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final drafts = snapshot.data!;
        if (drafts.isEmpty) {
          return const EmptyState(
            icon: Icons.inbox_outlined,
            message: 'No hay operaciones tardías registradas.',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            for (final draft in drafts)
              Card(
                child: ListTile(
                  key: Key('late-draft-${draft['draft_ref']}'),
                  title: Text(
                    '${_kind(draft['kind'])} · ${formatDate(draft['effective_date'])} · ${draft['campaign_name']}',
                  ),
                  subtitle: Text(
                    [
                      'Motivo: ${draft['reason']}',
                      switch (draft['status']) {
                        'PENDING' =>
                          'Pendiente de revisión: sin efectos todavía',
                        'CONFIRMED' => 'Confirmada por el titular',
                        _ => 'Rechazada',
                      },
                      if (draft['status'] == 'PENDING' &&
                          draft['last_conflict_code'] != null)
                        draft['last_conflict_code'] ==
                                LateConflict.stockUnavailable
                            ? 'Último intento: las existencias de esa fecha no alcanzan'
                            : 'Último intento: la fecha ya no corresponde a esa campaña',
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  trailing: draft['status'] != 'PENDING'
                      ? null
                      : Wrap(
                          children: [
                            IconButton(
                              key: Key('late-confirm-${draft['draft_ref']}'),
                              tooltip: 'Confirmar',
                              onPressed: _busy
                                  ? null
                                  : () => _resolve(draft, confirm: true),
                              icon: const Icon(Icons.check_circle_outline),
                            ),
                            IconButton(
                              key: Key('late-reject-${draft['draft_ref']}'),
                              tooltip: 'Rechazar',
                              onPressed: _busy
                                  ? null
                                  : () => _resolve(draft, confirm: false),
                              icon: const Icon(Icons.cancel_outlined),
                            ),
                          ],
                        ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
