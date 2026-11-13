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
  JointPurchaseErrorCodes.consentVersionRetired =>
    'se preparó con un texto anterior que ya no se acepta',
  JointPurchaseErrorCodes.appUpdateRequired =>
    'hay que actualizar la aplicación',
  JointPurchaseErrorCodes.wideningNotAllowed =>
    'la convocatoria está cancelada',
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

/// Chips de una convocatoria en la lista: «Nueva», su estado, el de la
/// participación propia y, para una participación con consentimiento
/// anterior a E4 (también cerrada), «Revisar autorización».
List<String> jointPurchaseChips(JointPurchaseCall call) => [
  if (call.isNew) 'Nueva',
  callStatusText(call),
  ?jointPurchaseOpText(call.latestOp),
  if (call.latestOp == null && call.acceptedActive != null)
    'Participación recibida',
  if (call.pendingConsentOp != null) 'Pendiente: quién ve sus datos',
  if (call.needsAccessReview) jointPurchaseAccessReviewChip,
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

// --- Quién ve sus datos (E4 §4 y §6.5) --------------------------------------
//
// Tratamiento de «usted». Lo que se anuncia como vigente es siempre lo que el
// sindicato tiene aplicado; lo pendiente se dice aparte, como pendiente. No se
// usa «anónimo»: un total sin nombres puede permitir deducir una cantidad.

/// Acción de la transición y de la autorización después de retirarla.
const jointPurchaseAccessReviewLabel =
    'Revisar quién puede ver mi participación';

/// Etiqueta de la lista para las participaciones con un consentimiento
/// anterior a E4 que todavía no se revisaron.
const jointPurchaseAccessReviewChip = 'Revisar autorización';

/// Acción que retira la autorización `CONV-4` sin retirar la participación
/// (D-05).
const jointPurchaseAccessRetractLabel = 'Retirar la autorización';

/// Casilla del diálogo de revisión: nunca marcada de antemano.
const jointPurchaseAccessReviewCheck =
    'Entiendo y acepto este texto para mi participación en esta convocatoria.';

/// Lo que explica el diálogo de retirada (la participación sigue).
const jointPurchaseAccessRetractDetail =
    'La Administración dejará de ver su nombre y sus cantidades cuando el '
    'sindicato reciba esta decisión; lo que ya se haya visto no se puede '
    'retirar. Su participación sigue vigente y sus cantidades siguen '
    'contando en los totales por producto, que se muestran sin nombres.';

/// Casilla del diálogo de retirada: nunca marcada de antemano.
const jointPurchaseAccessRetractCheck =
    'Quiero retirar la autorización y conservar mi participación.';

/// En los dos diálogos: decidir quién ve los datos no cambia el pedido.
const jointPurchaseQuantitiesUnchanged = 'Sus cantidades no cambian.';

/// Quién ve el nombre y las cantidades del agricultor en esta convocatoria,
/// según lo que el sindicato tiene **aplicado** (nunca lo que sólo está
/// pendiente en el teléfono). Sin participación en el sindicato, lo que
/// regirá al participar.
String jointPurchaseWhoCanSeeText(JointPurchaseCall call) {
  const withConsent =
      'la Administración habilitada de su sindicato podrá ver su nombre y sus '
      'cantidades, y la Directiva sólo los totales por producto, sin su '
      'nombre';
  const nobody =
      'nadie de la Directiva ni de la Administración ve su nombre ni sus '
      'cantidades';
  final server = call.serverParticipation;
  if (server == null) {
    return switch (call.pendingInitialScope) {
      null => 'Si participa, $withConsent.',
      JointPurchaseConsentScope.administration =>
        'Su participación todavía no llegó al sindicato. Cuando llegue, '
            '$withConsent.',
      _ =>
        'Su participación todavía no llegó al sindicato y se preparó con un '
            'texto anterior: cuando llegue, $nobody hasta que usted revise '
            'quién puede ver su participación.',
    };
  }
  if (!server.isActive) {
    return 'Su participación está retirada: no se cuenta en los totales ni '
        'aparece en el detalle de la Administración.';
  }
  return switch (server.consentScope) {
    JointPurchaseConsentScope.administration =>
      'La Administración habilitada de su sindicato puede ver su nombre y sus '
          'cantidades. La Directiva sólo ve los totales por producto, sin su '
          'nombre.',
    JointPurchaseConsentScope.totalsOnly =>
      'Usted retiró la autorización: $nobody. Sus cantidades siguen contando '
          'en los totales por producto, que se muestran sin nombres.',
    // Verificación E4 (D2): en una cancelada no hay revisión (E4 §4.2), así
    // que no se invita a hacerla.
    _ when call.status == JointPurchaseCallStatus.cancelled =>
      'Su participación se registró con un texto anterior. La convocatoria '
          'está cancelada y ya no admite cambios: $nobody.',
    _ =>
      'Su participación se registró con un texto anterior. Con las reglas '
          'actuales, $nobody hasta que usted revise quién puede ver su '
          'participación. Mientras tanto, los totales de los productos que '
          'pidió pueden no mostrarse.',
  };
}

/// Lo que dice el detalle de una decisión preparada que todavía no llegó:
/// nunca se anuncia como aplicada.
String jointPurchaseConsentPendingText(JointPurchaseConsentOp op) {
  if (op.isRetiredOption) {
    return 'Pendiente de envío: una decisión preparada con un texto anterior '
        '(ampliar a otras personas o autorizar a la persona responsable). Esa '
        'opción ya no existe: el sindicato no la aplicará y seguirá rigiendo '
        'lo que se indica arriba.';
  }
  return switch (op.scope) {
    JointPurchaseConsentScope.administration =>
      'Pendiente de envío: autorizar a la Administración a ver su nombre y sus '
          'cantidades. Hasta que el sindicato la reciba, no está aplicada y '
          'rige lo que se indica arriba.',
    JointPurchaseConsentScope.totalsOnly =>
      'Pendiente de envío: retirar la autorización. Hasta que el sindicato la '
          'reciba, no está aplicada y rige lo que se indica arriba.',
    _ =>
      'Pendiente de envío: reducir quién ve sus datos (decisión preparada con '
          'un texto anterior). Hasta que el sindicato la reciba, no está '
          'aplicada y rige lo que se indica arriba.',
  };
}

/// Resultado de la última decisión enviada, o null si no hay nada que decir.
String? jointPurchaseConsentResultText(JointPurchaseCall call) {
  final op = call.latestConsentOp;
  if (op == null || op.isAwaitingSend) return null;
  return switch (op.sendStatus) {
    JointPurchaseOpStatus.received =>
      op.lastCode == JointPurchaseCodes.responseUnreadable
          ? 'El sindicato recibió su última decisión sobre quién ve sus datos, '
                'pero esta aplicación no pudo leer su respuesta. Pulse '
                '«Actualizar» en Compras conjuntas.'
          : 'Su última decisión sobre quién ve sus datos está aplicada en el '
                'sindicato.',
    JointPurchaseOpStatus.rejected => switch (op.lastCode) {
      JointPurchaseErrorCodes.consentVersionRetired =>
        'El sindicato no aplicó una decisión preparada con un texto anterior: '
            'esa opción ya no existe. Rige lo que se indica arriba.',
      JointPurchaseErrorCodes.wideningNotAllowed =>
        'El sindicato no aplicó su decisión: la convocatoria está cancelada. '
            'Rige lo que se indica arriba.',
      JointPurchaseErrorCodes.appUpdateRequired =>
        'El sindicato pide actualizar la aplicación para aplicar su decisión. '
            'Rige lo que se indica arriba.',
      JointPurchaseErrorCodes.participationRequired =>
        'El sindicato no aplicó su decisión: no tiene una participación suya en '
            'esta convocatoria.',
      _ =>
        'El sindicato no aplicó su última decisión sobre quién ve sus datos '
            '(${op.lastCode ?? 'sin código'}). Rige lo que se indica arriba.',
    },
    JointPurchaseOpStatus.superseded when op.lastCode != null =>
      'Una decisión suya posterior ya estaba aplicada en el sindicato; la '
          'anterior quedó sin efecto.',
    _ => null,
  };
}
