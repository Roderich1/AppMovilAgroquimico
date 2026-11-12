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
      JointPurchaseHistoryOutcome.incompatibleVersion =>
        jointPurchaseIncompatibleText,
      JointPurchaseHistoryOutcome.unavailable =>
        'No se pudo leer el historial del sindicato. Lo guardado en el '
            'teléfono se conserva; inténtelo más tarde.',
    };

// --- N7: por qué no se pudo leer (E2 §10.6) ---------------------------------

/// El sindicato usa otra versión: no es un fallo de conexión ni temporal.
const jointPurchaseIncompatibleText =
    'Esta versión de la aplicación ya no puede leer las compras conjuntas '
    'del sindicato. Actualice la aplicación. Lo guardado en el teléfono, '
    'incluido lo pendiente de envío, se conserva.';

const jointPurchaseListOfflineText =
    'Sin conexión: no se pudo consultar al sindicato. Lo guardado en el '
    'teléfono se conserva y lo pendiente se enviará al conectarse.';

const jointPurchaseListTemporaryText =
    'El sindicato no respondió correctamente. Lo guardado en el teléfono se '
    'conserva; inténtelo más tarde.';

// --- Autorización (E2 §10.6, P-C) -------------------------------------------

/// Título de la acción que amplía quién ve los datos.
const jointPurchaseWidenLabel =
    'Autorizar también a la Directiva o la '
    'Administración';

/// Título de la acción que reduce a sólo la persona responsable.
const jointPurchaseReduceLabel = 'Reducir a sólo la persona responsable';

/// Casilla de la ampliación: nunca marcada de antemano.
const jointPurchaseWidenCheck =
    'Autorizo que también vean mi nombre y mis cantidades las personas de la '
    'Directiva o la Administración que la persona responsable autorice para '
    'esta convocatoria.';

const jointPurchaseReduceDetail =
    'Sólo la persona responsable podrá ver su nombre y sus cantidades. Las '
    'personas que ella autorizó dejarán de verlos cuando el sindicato reciba '
    'esta decisión; lo que ya hayan visto no se puede retirar. Sus cantidades '
    'no cambian.';

/// Lo que dice el detalle de una decisión preparada que todavía no llegó:
/// nunca se anuncia como aplicada.
String jointPurchaseConsentPendingText(JointPurchaseConsentOp op) =>
    op.isWidening
    ? 'Pendiente de envío: autorizar también a la Directiva o la '
          'Administración. Hasta que el sindicato la reciba, rige lo anterior.'
    : 'Pendiente de envío: reducir a sólo la persona responsable. Hasta que '
          'el sindicato la reciba, la reducción no está aplicada y rige lo '
          'anterior.';

/// Resultado de la última decisión enviada, o null si no hay nada que decir.
String? jointPurchaseConsentResultText(JointPurchaseCall call) {
  final op = call.latestConsentOp;
  if (op == null || op.isAwaitingSend) return null;
  return switch (op.sendStatus) {
    JointPurchaseOpStatus.received =>
      'Su última decisión sobre quién ve sus datos está aplicada en el '
          'sindicato.',
    JointPurchaseOpStatus.rejected =>
      'El sindicato no aplicó su última decisión sobre quién ve sus datos '
          '(${op.lastCode ?? 'sin código'}). Rige lo que se indica arriba.',
    JointPurchaseOpStatus.superseded when op.lastCode != null =>
      'Una decisión suya posterior ya estaba aplicada en el sindicato; la '
          'anterior quedó sin efecto.',
    _ => null,
  };
}

/// E2 §10.3 y §10.6: quién puede ver, por función, el nombre y las
/// cantidades del agricultor en esta convocatoria, según el alcance que el
/// sindicato tiene **aplicado** (nunca lo que sólo está pendiente en el
/// teléfono). Sin participación en el sindicato, lo que regiría al
/// participar: sólo la persona responsable, con la opción de ampliar después.
String jointPurchaseWhoCanSeeText(JointPurchaseCall call) {
  final responsible = call.responsibleName == null
      ? 'la persona responsable'
      : 'la persona responsable (${call.responsibleName})';
  const authorized =
      'las personas de la Directiva o la Administración que ella autorice '
      'para esta convocatoria';
  final server = call.serverParticipation;
  if (server == null) {
    return 'Si participa, sólo $responsible podrá ver su nombre y sus '
        'cantidades. Después podrá autorizar, si quiere, también a '
        '$authorized.';
  }
  // P-A C1 (E2 §12): la responsable cambió y el sindicato dice que usted
  // todavía no la autorizó: nadie ve sus datos, tampoco quienes ella autorice.
  if (server.needsResponsibleAuthorization) {
    return 'Por ahora nadie de la Directiva ni de la Administración puede ver '
        'su nombre ni sus cantidades: la persona responsable cambió y usted '
        'todavía no autorizó a $responsible.';
  }
  if (server.coversCollaborators) {
    return 'Pueden ver su nombre y sus cantidades $responsible y '
        '$authorized, porque usted lo autorizó.';
  }
  return 'Sólo $responsible puede ver su nombre y sus cantidades.';
}

// --- Nueva persona responsable (E2 §12, P-A C1) ------------------------------

/// Título de la acción que autoriza a la persona responsable actual.
const jointPurchaseResponsibleReviewLabel = 'Revisar autorización';

String _responsibleOf(JointPurchaseCall call) =>
    call.responsibleName ?? 'la nueva persona responsable';

/// Aviso del detalle: la responsable cambió y no se supone nada.
String jointPurchaseResponsibleChangedText(JointPurchaseCall call) =>
    'La persona responsable de esta compra conjunta cambió: ahora es '
    '${_responsibleOf(call)}. Su autorización anterior no vale para ella: no '
    'puede ver su nombre ni sus cantidades hasta que usted la autorice. Su '
    'participación y sus cantidades no cambian.';

/// Una autorización preparada que todavía no llegó: nunca se anuncia como
/// aplicada.
String jointPurchaseResponsiblePendingText(JointPurchaseCall call) =>
    'Autorización pendiente de envío. Hasta que el sindicato la reciba, '
    '${_responsibleOf(call)} sigue sin ver sus datos.';

/// La responsable volvió a cambiar antes de que llegara la autorización.
const jointPurchaseResponsibleOutdatedText =
    'La persona responsable volvió a cambiar antes de que llegara su '
    'autorización: esa autorización no vale para la nueva. Revise de nuevo.';

/// Casilla principal del diálogo: nunca marcada de antemano.
String jointPurchaseResponsibleCheck(JointPurchaseCall call) =>
    'Autorizo a ${_responsibleOf(call)} a ver mi nombre y las cantidades que '
    'solicito en esta convocatoria, para coordinar la compra y la entrega.';

/// Segunda casilla, aparte y sin marcar: autorizar sólo a la responsable no
/// amplía a nadie más.
const jointPurchaseResponsibleCollaboratorsCheck =
    'También autorizo a las personas de la Directiva o la Administración que '
    'ella autorice para esta convocatoria.';
