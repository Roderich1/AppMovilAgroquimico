import 'package:intl/intl.dart';

import '../../data/sync/joint_purchase_store.dart';
import '../../domain/money.dart' show formatQuantity;
import '../../domain/sync/joint_purchase_call_view.dart';
import '../../services/sync/joint_purchase_sender.dart'
    show JointPurchaseHistoryOutcome, JointPurchaseHistoryResult;

/// Instante del servidor (UTC) mostrado en la hora de este teléfono:
/// `dd/MM/yyyy HH:mm`. Patrón numérico sin locale (como `formatDate`).
String formatCallInstant(String iso) {
  final parsed = DateTime.tryParse(iso)?.toLocal();
  return parsed == null ? iso : DateFormat('dd/MM/yyyy HH:mm').format(parsed);
}

/// «Fecha límite: … (según la hora del sindicato)» (E2-D4, E2 §5.2).
String callDeadlineText(JointPurchaseCall call) =>
    'Fecha límite: ${formatCallInstant(call.deadlineAt)} '
    '(según la hora del sindicato)';

/// Aviso de Inicio (E2-D15).
String jointPurchaseNoticeText(JointPurchaseNotice notice) =>
    'Nueva convocatoria: ${notice.name} · cierra el '
    '${formatCallInstant(notice.deadlineAt)}'
    '${notice.total > 1 ? ' (y ${notice.total - 1} más)' : ''}';

/// Estado de la convocatoria según la última copia del sindicato.
String callStatusText(JointPurchaseCall call) => switch (call.status) {
  JointPurchaseCallStatus.open => 'Abierta',
  JointPurchaseCallStatus.closed => 'Convocatoria cerrada',
  JointPurchaseCallStatus.cancelled => 'Convocatoria cancelada',
  _ => call.status,
};

/// Motivo legible de un rechazo (E2 §4.2). Nunca muestra datos del cuerpo.
String jointPurchaseReason(String? code) => switch (code) {
  'CONSENT_REQUIRED' => 'falta el consentimiento',
  'PRODUCT_NOT_IN_CALL' => 'un producto no pertenece a la convocatoria',
  'QUANTITY_INVALID' => 'una cantidad no es válida',
  'PAYLOAD_INVALID' => 'los datos no tienen el formato esperado',
  'OPERATION_ID_REUSED' =>
    'el identificador de la operación ya se usó con otro contenido',
  'CALL_NOT_FOUND' => 'la convocatoria no existe para su cuenta',
  JointPurchaseCodes.callDraft => 'la convocatoria todavía no está abierta',
  _ => 'el sindicato no la aceptó',
};

/// Estado de la última operación propia (E2 §5.4). Nunca «recibida» para
/// lo que sólo existe en el teléfono.
String? jointPurchaseOpText(JointPurchaseOp? op) {
  if (op == null) return null;
  return switch (op.sendStatus) {
    JointPurchaseOpStatus.pendingSend =>
      op.isRetryScheduled
          ? 'Pendiente de envío (se reintentará)'
          : 'Pendiente de envío',
    JointPurchaseOpStatus.authPaused =>
      'Pendiente: verifique el acceso en línea',
    JointPurchaseOpStatus.received =>
      op.isWithdraw ? 'Retiro recibido' : 'Participación recibida',
    JointPurchaseOpStatus.outOfTime => 'Fuera de plazo',
    JointPurchaseOpStatus.rejected => switch (op.lastCode) {
      JointPurchaseCodes.callClosed => 'Convocatoria cerrada',
      JointPurchaseCodes.callCancelled => 'Convocatoria cancelada',
      _ => 'Rechazada: ${jointPurchaseReason(op.lastCode)}',
    },
    JointPurchaseOpStatus.superseded =>
      op.lastCode == JointPurchaseCodes.staleSequence
          ? 'Sin efecto: el sindicato ya tenía un cambio más reciente'
          : null,
    _ => null,
  };
}

/// Chips de una convocatoria en la lista: «Nueva», su estado y el de la
/// participación propia.
List<String> jointPurchaseChips(JointPurchaseCall call) => [
  if (call.isNew) 'Nueva',
  callStatusText(call),
  ?jointPurchaseOpText(call.latestOp),
  if (call.latestOp == null && call.acceptedActive != null)
    'Participación recibida',
];

/// «25 L de Herbicida, 10 KG de Fungicida» con los productos de [call].
String linesText(JointPurchaseCall call, Map<String, int> lines) => [
  for (final entry in lines.entries)
    '${formatQuantity(entry.value, call.product(entry.key)?.unit ?? '')} de '
        '${call.product(entry.key)?.name ?? 'producto'}',
].join(', ');

/// «El sindicato tiene: …» (lo último aceptado), o null si nunca aceptó
/// nada de este titular. En una convocatoria cerrada, si entró o no al
/// consolidado.
String? acceptedText(JointPurchaseCall call) {
  final participation = call.serverParticipation;
  // En una convocatoria cerrada, lo guardado es lo que entró al
  // consolidado al cierre (E2 §4.2).
  if (call.status == JointPurchaseCallStatus.closed) {
    return participation?.isActive == true
        ? 'Incluida en el consolidado al cierre: '
              '${linesText(call, participation!.lines)}'
        : 'No incluida en el consolidado al cierre';
  }
  if (participation == null) return null;
  return participation.isActive
      ? 'El sindicato tiene: ${linesText(call, participation.lines)}'
      : 'El sindicato tiene: participación retirada';
}

/// «Pendiente de envío: …» del cambio local que todavía no llegó.
String? pendingText(JointPurchaseCall call) {
  final op = call.pendingOp;
  if (op == null) return null;
  return op.isWithdraw
      ? 'Pendiente de envío: retiro de la participación'
      : 'Pendiente de envío: ${linesText(call, op.lines)}';
}

// --- Historial (E2 §10.1) ------------------------------------------------

const jointPurchaseHistoryTitle = 'Historial';

const jointPurchaseHistoryIntro =
    'Convocatorias terminadas hace más de $jointPurchaseRecentFinishedDays '
    'días. Las guardadas en este teléfono se ven también sin conexión.';

const jointPurchaseHistoryEmpty =
    'No hay convocatorias anteriores guardadas en este teléfono.';

/// Texto exacto de E2 §10.1 cuando no se pudo consultar al sindicato.
const jointPurchaseHistoryOfflineText =
    'Sin conexión: las convocatorias anteriores que no están en este '
    'teléfono se pueden consultar al conectarse.';

const jointPurchaseHistoryEnd =
    'No hay más convocatorias anteriores en el sindicato.';

const jointPurchaseRecentEmpty =
    'No hay convocatorias abiertas ni recientes en este teléfono. Pulse '
    '«Actualizar» para consultar al sindicato.';

/// «Hay N convocatorias anteriores que no están en este teléfono» (E2
/// §10.1), con el `older_count` de la última actualización.
String jointPurchaseMissingOlderText(int missing) => missing == 1
    ? 'Hay 1 convocatoria anterior que no está en este teléfono.'
    : 'Hay $missing convocatorias anteriores que no están en este teléfono.';

/// Aviso tras «Consultar historial» o «Ver más», o null si todo fue bien.
String? historyProblemText(JointPurchaseHistoryResult result) =>
    switch (result.outcome) {
      JointPurchaseHistoryOutcome.saved => null,
      JointPurchaseHistoryOutcome.offline => jointPurchaseHistoryOfflineText,
      JointPurchaseHistoryOutcome.authFailed =>
        'El sindicato pidió verificar el acceso otra vez. Lo guardado en el '
            'teléfono se conserva.',
      JointPurchaseHistoryOutcome.ownerMismatch =>
        'La cuenta en sesión no es la del titular: no se consultó nada.',
      JointPurchaseHistoryOutcome.apiUnavailable =>
        'Este teléfono no tiene configurado el servidor del sindicato.',
      JointPurchaseHistoryOutcome.invalidCursor =>
        'El sindicato no reconoció la página pedida. Pulse «Consultar '
            'historial» para empezar de nuevo.',
      JointPurchaseHistoryOutcome.unavailable =>
        'No se pudo leer el historial del sindicato. Lo guardado en el '
            'teléfono se conserva; inténtelo más tarde.',
    };
