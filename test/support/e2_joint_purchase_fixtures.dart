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
  Map<String, Object?> extra = const {},
}) => {
  'call_id': id,
  'name': name,
  'status': status,
  'campaign': {'campaign_ref': campaignRef, 'name': 'Campaña sindicato 2026'},
  'opened_at': '2026-11-10T12:00:00.000Z',
  'deadline_at': deadlineAt,
  'closed_at': status == 'CLOSED' ? '2026-11-20T22:00:00.000Z' : null,
  'cancelled_at': status == 'CANCELLED' ? '2026-11-12T10:00:00.000Z' : null,
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
    'version': 'CONV-1',
    'accepted_at': '2026-11-11T18:20:00.000Z',
    'received_at': acceptedAt,
  },
};

/// Raíz de la lista (`contractVersion`, `server_time`, `consent`, `calls`).
Map<String, Object?> listJson(List<Map<String, Object?>> calls) => {
  'contractVersion': 1,
  'server_time': '2026-11-11T18:20:05.120Z',
  'consent': {
    'version': jointPurchaseConsentVersion,
    'text': jointPurchaseConsentText,
  },
  'calls': calls,
};

http.Response jsonResponse(Object body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Guarda [calls] como si el sindicato los hubiera servido a [scope].
Future<void> seedCalls(
  JointPurchaseStore store,
  OwnerScope scope,
  List<Map<String, Object?>> calls,
) => store.saveFetched(
  scope,
  JointPurchaseCallView.listFromJson(listJson(calls)),
);
