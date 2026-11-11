import '../../data/sync/identification_request_store.dart';

/// Motivo legible de un código de rechazo o de fallo (E1 §4.1). Nunca
/// muestra datos del cuerpo recibido.
String identificationReason(String? code) => switch (code) {
  'PAYLOAD_INVALID' => 'los datos no tienen el formato esperado',
  'UNIT_UNSUPPORTED' => 'la unidad no es L ni KG',
  'UNIT_IMMUTABLE' => 'la unidad no puede cambiar',
  'REQUEST_ID_CONFLICT' => 'el identificador de la solicitud ya está en uso',
  'IMAGE_INVALID' => 'la imagen no es válida',
  'IMAGE_TOO_LARGE' => 'la imagen es demasiado grande',
  'PHOTO_CONSENT_REQUIRED' => 'falta el consentimiento de la foto',
  'PHOTO_MISSING' => 'la foto autorizada ya no está en este teléfono',
  _ => 'el sindicato no la aceptó',
};

/// Textos de estado de una solicitud (contrato E1 §5.6), en orden. Nunca
/// «Enviado» para una solicitud que sólo existe en el teléfono: «Recibida»
/// sólo aparece tras la respuesta del sindicato.
List<String> identificationChips(IdentificationRequest request) => [
  ...switch (request.sendStatus) {
    IdentificationSendStatus.pendingSend ||
    IdentificationSendStatus.authPaused => const ['Pendiente de envío'],
    IdentificationSendStatus.rejected => [
      'Rechazada: ${identificationReason(request.lastCode)}',
    ],
    _ =>
      request.isLinked
          ? ['Identificado como “${request.serverProductName}”']
          : [
              'Recibida por el sindicato',
              if (request.serverStatus == 'PENDING') 'Esperando identificación',
            ],
  },
  ...switch (request.photoSendStatus) {
    IdentificationPhotoStatus.pendingSend => const ['Foto pendiente de envío'],
    IdentificationPhotoStatus.sent => const ['Foto enviada'],
    IdentificationPhotoStatus.failed =>
      request.photoRetryable
          ? const ['Foto no enviada (se reintentará)']
          : ['Foto no enviada: ${identificationReason(request.photoLastCode)}'],
    IdentificationPhotoStatus.removePending => const [
      'Retiro de la foto pendiente de envío',
    ],
    IdentificationPhotoStatus.removed => const ['Foto retirada'],
    _ => const <String>[],
  },
];

/// ¿Tiene sentido «Enviar ahora»? Datos pendientes o pausados, o una foto
/// pendiente, con reintento o con el retiro pendiente.
bool identificationCanSendNow(IdentificationRequest request) =>
    request.sendStatus == IdentificationSendStatus.pendingSend ||
    request.sendStatus == IdentificationSendStatus.authPaused ||
    (request.sendStatus == IdentificationSendStatus.received &&
        (request.photoSendStatus == IdentificationPhotoStatus.pendingSend ||
            request.photoSendStatus ==
                IdentificationPhotoStatus.removePending ||
            request.photoRetryable));

/// «Identificado por el sindicato como “X” (L)», o null si no lo está.
String? identificationLinkedText(IdentificationRequest request) =>
    request.isLinked
    ? 'Identificado por el sindicato como “${request.serverProductName}”'
          '${request.serverProductUnit == null ? '' : ' (${request.serverProductUnit})'}'
    : null;
