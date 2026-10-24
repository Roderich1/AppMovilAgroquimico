import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show repositoryProvider;
import '../../services/auth/local_owner_credential.dart';
import '../../services/auth/local_owner_credential_providers.dart';
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
    builder: (context) => _ReasonDialog(
      title: title,
      effects: effects,
      confirmLabel: confirmLabel,
    ),
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

/// RF-13 §1.3: el texto de quién autorizó una reversión.
/// - [readFailed]: no se pudo leer la auditoría. No es lo mismo que no
///   tenerla, así que no se presenta como «sin actor» (R1 de C).
/// - Sin auditoría ([audit] null): reversión anterior a v11, «Actor no
///   registrado»; no se infiere nadie.
/// - Con auditoría, se compara su enrolamiento con el PIN configurado ahora
///   ([currentEnrolmentId]; [enrolmentReadable] false si no se pudo leer).
///   Si no coincide, la autorizó el titular con un PIN que ya no está aquí:
///   uno anterior a restablecerlo o el de otra instalación (base restaurada).
///   El enrolamiento no distingue esos dos casos, así que no se afirma
///   ninguno (R2 de C).
String reversalActorLabel(
  Map<String, Object?>? audit, {
  bool readFailed = false,
  String? currentEnrolmentId,
  bool enrolmentReadable = true,
}) {
  if (readFailed) return 'No se pudo leer quién autorizó esta reversión';
  if (audit == null) return 'Actor no registrado';
  final how = !enrolmentReadable
      ? 'con su PIN (no se pudo comprobar en este teléfono)'
      : audit['credential_enrolment_ref'] == currentEnrolmentId
      ? 'con el PIN de este teléfono'
      : 'con un PIN que ya no está configurado en este teléfono '
            '(anterior o de otra instalación)';
  return 'Autorizada por el titular $how · ${audit['reason']}';
}

typedef _ActorInfo = ({
  Map<String, Object?>? audit,
  String? enrolmentId,
  bool enrolmentReadable,
});

/// Quién autorizó una reversión ([reversalActorLabel]).
class ReversalActorText extends ConsumerWidget {
  const ReversalActorText({
    super.key,
    required this.operationType,
    required this.operationId,
  });

  final String operationType;
  final int operationId;

  Future<_ActorInfo> _load(WidgetRef ref) async {
    final audit = await ref
        .read(repositoryProvider)
        .reversalAudit(operationType, operationId);
    if (audit == null) {
      return (audit: null, enrolmentId: null, enrolmentReadable: true);
    }
    try {
      final enrolmentId = await ref
          .read(localOwnerCredentialProvider)
          .currentEnrolmentId();
      return (audit: audit, enrolmentId: enrolmentId, enrolmentReadable: true);
    } on Object {
      return (audit: audit, enrolmentId: null, enrolmentReadable: false);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      FutureBuilder<_ActorInfo>(
        future: _load(ref),
        builder: (context, snapshot) {
          if (!snapshot.hasData && !snapshot.hasError) {
            return const SizedBox.shrink();
          }
          final info = snapshot.data;
          final text = reversalActorLabel(
            info?.audit,
            readFailed: snapshot.hasError,
            currentEnrolmentId: info?.enrolmentId,
            enrolmentReadable: info?.enrolmentReadable ?? true,
          );
          return Text(
            text,
            key: Key('reversal-actor-$operationType-$operationId'),
            style: Theme.of(context).textTheme.bodySmall,
          );
        },
      );
}
