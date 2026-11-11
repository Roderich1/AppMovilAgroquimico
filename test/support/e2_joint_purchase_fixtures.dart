// Soporte de pruebas de las convocatorias de compra conjunta (contrato E2
// §4.2 y §5). Datos sintéticos.
import 'dart:convert';

import 'package:agroquimicos/data/sync/joint_purchase_store.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/sync/joint_purchase_call_view.dart';
import 'package:http/http.dart' as http;

import 'f05_sync_fixtures.dart';

/// Convocatoria sintética (UUID v4 en minúsculas).
const callId = '7b1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
const otherCallId = '8b1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';

/// Fecha límite en el futuro respecto de los relojes de las pruebas.
const deadline = '2026-11-20T22:00:00.000Z';

/// Un elemento de `GET /me/joint-purchase-calls` con la forma del Backend
/// (`FarmerCallView`).
Map<String, Object?> callJson({
  String id = callId,
  String name = 'Compra conjunta de herbicida',
  String status = 'OPEN',
  String deadlineAt = deadline,
  Map<String, Object?>? participation,
  Map<String, Object?>? closing,
  bool withKilo = true,
  String closedAt = '2026-11-20T22:00:00.000Z',
  String cancelledAt = '2026-11-12T10:00:00.000Z',
  Map<String, Object?> extra = const {},
}) => {
  'call_id': id,
  'name': name,
  'status': status,
  'campaign': {'campaign_ref': campaignRef, 'name': 'Campaña sindicato 2026'},
  'opened_at': '2026-11-10T12:00:00.000Z',
  'deadline_at': deadlineAt,
  'closed_at': status == 'CLOSED' ? closedAt : null,
  'cancelled_at': status == 'CANCELLED' ? cancelledAt : null,
  'server_time': '2026-11-11T18:20:05.120Z',
  'accepts_operations': status == 'OPEN',
  'responsible': {'name': 'Responsable sintético'},
  'products': [
    {
      'product_ref': litreRef,
      'name': 'Herbicida central',
      'unit': 'L',
      'base_unit': 'ML',
    },
    if (withKilo)
      {
        'product_ref': kiloRef,
        'name': 'Fungicida central',
        'unit': 'KG',
        'base_unit': 'G',
      },
  ],
  'participation': participation,
  'closing': closing,
  ...extra,
};

/// Unidad base de los productos sintéticos.
String baseUnitOf(String ref) => ref == kiloRef ? 'G' : 'ML';

/// Participación aceptada tal como la sirve el servidor (`ParticipationView`).
Map<String, Object?> participationJson({
  Map<String, int> lines = const {litreRef: 25000},
  int lastSequence = 1,
  String lastOperationId = '6c1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d',
  String acceptedAt = '2026-11-11T18:21:00.000Z',
  bool withdrawn = false,
  String consentVersion = jointPurchaseConsentVersion,
}) => {
  'status': withdrawn ? 'WITHDRAWN' : 'ACTIVE',
  'lines': withdrawn
      ? <Object?>[]
      : [
          for (final entry in lines.entries)
            {
              'product_ref': entry.key,
              'base_unit': baseUnitOf(entry.key),
              'quantity_base': '${entry.value}',
            },
        ],
  'last_sequence': lastSequence,
  'last_operation_id': lastOperationId,
  'accepted_at': acceptedAt,
  'consent': {
    'version': consentVersion,
    'accepted_at': '2026-11-11T18:20:00.000Z',
    'received_at': acceptedAt,
  },
};

/// Raíz de la vista por defecto (`contractVersion`, `server_time`,
/// `consent`, `history`, `calls`).
Map<String, Object?> listJson(
  List<Map<String, Object?>> calls, {
  int olderCount = 0,
  String serverTime = '2026-11-11T18:20:05.120Z',
}) => {
  'contractVersion': 1,
  'server_time': serverTime,
  'consent': {
    'version': jointPurchaseConsentVersion,
    'text': jointPurchaseConsentText,
  },
  'history': {'older_count': olderCount},
  'calls': calls,
};

/// Una página de `GET /me/joint-purchase-calls/history` (E2 §10.1).
Map<String, Object?> historyJson(
  List<Map<String, Object?>> calls, {
  String? nextCursor,
}) => {
  'contractVersion': 1,
  'server_time': '2026-11-11T18:20:05.120Z',
  'calls': calls,
  'next_cursor': nextCursor,
};

/// Convocatoria terminada hace más de 180 días (respecto de los relojes de
/// las pruebas, 2026-11-11) con participación propia, como la sirve el
/// historial.
Map<String, Object?> oldCallJson(
  String id, {
  String status = 'CLOSED',
  String finishedAt = '2026-03-01T12:00:00.000Z',
  Map<String, Object?>? participation,
}) => callJson(
  id: id,
  name: 'Compra anterior $id',
  status: status,
  deadlineAt: '2026-02-28T22:00:00.000Z',
  closedAt: finishedAt,
  cancelledAt: finishedAt,
  participation: participation ?? participationJson(),
  closing: status == 'CLOSED'
      ? {
          'cutoff_at': '2026-02-28T22:00:00.000Z',
          'closed_at': finishedAt,
          'included': true,
          'lines': [
            {
              'product_ref': litreRef,
              'base_unit': 'ML',
              'quantity_base': '25000',
            },
          ],
        }
      : null,
  extra: const {'opened_at': '2026-02-01T12:00:00.000Z'},
);

http.Response jsonResponse(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Guarda [calls] como si el sindicato los hubiera servido a [scope] en la
/// vista por defecto.
Future<void> seedCalls(
  JointPurchaseStore store,
  OwnerScope scope,
  List<Map<String, Object?>> calls, {
  int olderCount = 0,
}) => store.saveFetched(
  scope,
  JointPurchaseCallList.fromJson(listJson(calls, olderCount: olderCount)),
);
