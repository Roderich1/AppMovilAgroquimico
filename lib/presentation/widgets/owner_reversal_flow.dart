import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show repositoryProvider;
import '../../services/auth/local_owner_credential.dart';
import '../screens/owner_credential_screen.dart';

/// Motivo y autorización del titular para una acción (RF-13, RF-03).
typedef OwnerApproval = ({String reason, OwnerAuthorization authorization});

/// Muestra la acción y sus efectos, exige un motivo y después la confirmación
/// del titular con su PIN (docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md
/// §1.1). Devuelve null si se cancela en cualquier paso. El actor sale de la
/// autorización, nunca de la pantalla.
Future<OwnerApproval?> requestOwnerApproval(
  BuildContext context,
  WidgetRef ref, {
  required AuthorizationPurpose purpose,
  required String subjectRef,
  required String title,
  required String effects,
  String confirmLabel = 'Continuar',
}) async {
  final reason = await showDialog<String>(
    context: context,
    builder: (context) =>
        _ReasonDialog(title: title, effects: effects, confirmLabel: confirmLabel),
  );
  if (reason == null || !context.mounted) return null;
  final authorization = await requestOwnerAuthorization(
    context,
    ref,
    purpose: purpose,
    subjectRef: subjectRef,
    title: title,
    effects: 'Confirme con el PIN del titular. Motivo: $reason',
  );
  if (authorization == null) return null;
  return (reason: reason, authorization: authorization);
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.effects,
    required this.confirmLabel,
  });

  final String title;
  final String effects;
  final String confirmLabel;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _reason.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Indique el motivo.');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.effects, key: const Key('approval-effects')),
          const SizedBox(height: 12),
          TextField(
            key: const Key('approval-reason'),
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
        key: const Key('approval-continue'),
        onPressed: _submit,
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

/// RF-13 §1.3: quién autorizó una reversión. Las anteriores a la auditoría
/// (v11) quedan «Actor no registrado»: no se infiere nadie. Una autorización
/// con la credencial de otra instalación (base restaurada) sigue siendo la del
/// titular registrado en la auditoría, no un error.
class ReversalActorText extends ConsumerWidget {
  const ReversalActorText({
    super.key,
    required this.operationType,
    required this.operationId,
  });

  final String operationType;
  final int operationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      FutureBuilder<Map<String, Object?>?>(
        future: ref
            .read(repositoryProvider)
            .reversalAudit(operationType, operationId),
        builder: (context, snapshot) {
          if (!snapshot.hasData && !snapshot.hasError &&
              snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          final audit = snapshot.data;
          final text = audit == null
              ? 'Actor no registrado'
              : 'Autorizada por el titular con su PIN · ${audit['reason']}';
          return Text(
            text,
            key: Key('reversal-actor-$operationType-$operationId'),
            style: Theme.of(context).textTheme.bodySmall,
          );
        },
      );
}
