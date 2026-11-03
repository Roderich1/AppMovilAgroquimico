// Soporte de pruebas de la estimación del consumo (F12-EST-07-MOB, #164).
// Respuestas SINTÉTICAS con la forma exacta de INT-09 v1, perfil FARMER.
import 'package:agroquimicos/domain/installation_access.dart';

const campaignWinter = '7a0b5c1e-2d3f-4a4b-8c5d-6e7f8091a2b3';
const campaignSummer = '8b1c6d2f-3e40-4b5c-9d6e-7f8091a2b3c4';
const productHerbicide = '9c2d7e30-4f51-4c6d-8e7f-8091a2b3c4d5';
const productFungicide = 'ad3e8f41-5062-4d7e-9f80-91a2b3c4d5e6';
const runRef = 'be4f9052-6173-4e8f-a091-a2b3c4d5e6f7';
const seasonRef = 'cf50a163-7284-4f90-b1a2-b3c4d5e6f708';

const farmerNotice =
    'Referencia calculada a partir de cifras publicadas; no es una necesidad '
    'ni una propuesta, no se suma a ellas y puede no estar actualizada.';

Map<String, Object?> _target(String campaign) => {
  'campaign_ref': campaign,
  'name': campaign == campaignWinter
      ? 'Objetivo sintético invierno 2019'
      : 'Objetivo sintético verano 2019',
  'status': 'PLANIFICADA',
  'start_date': '2019-09-01T00:00:00.000Z',
  'end_date': null,
};

const _season = {
  'season_ref': seasonRef,
  'key': 'INVIERNO',
  'definition': 'Temporada sintética INVIERNO',
  'duration_days': 180,
};

Map<String, Object?> estimatedResult(String validityKey) => {
  'product': {'product_ref': productHerbicide, 'name': 'Herbicida de ensayo'},
  'base_unit': 'ML',
  'presentation_unit': 'L',
  'status': 'ESTIMATED',
  'reason_code': null,
  'method': 'SES_NAIVE',
  'run_ref': runRef,
  'generated_at': '2026-11-02T22:04:26.082Z',
  'span_length': 4,
  'estimate_base': '111000.000000',
  'validity_reason': null,
  validityKey: 'CURRENT',
};

Map<String, Object?> insufficientResult(String validityKey) => {
  'product': {'product_ref': productFungicide, 'name': 'Fungicida de ensayo'},
  'base_unit': 'ML',
  'presentation_unit': 'L',
  'status': 'INSUFFICIENT_DATA',
  'reason_code': 'SPAN_TOO_SHORT',
  'method': 'SES_NAIVE',
  'run_ref': runRef,
  'generated_at': '2026-11-02T22:04:27.000Z',
  'span_length': 2,
  'estimate_base': null,
  'validity_reason': 'NO_FIGURE',
  validityKey: 'NOT_USABLE',
};

/// Cuerpo de `GET /estimation/download` (perfil FARMER).
Map<String, Object?> farmerDownloadJson({
  OwnerScope scope = const OwnerScope(
    memberId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    tenantId: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  ),
  String campaign = campaignWinter,
  String downloadedAt = '2026-11-02T22:04:34.800Z',
  List<Map<String, Object?>>? results,
}) => {
  'contract_version': 1,
  'kind': 'ESTIMATION_DOWNLOAD',
  'profile': 'FARMER',
  'scope': {'tenant_ref': scope.tenantId},
  'subject': {'member_ref': scope.memberId, 'role': 'AGRICULTOR'},
  'downloaded_at': downloadedAt,
  'target': _target(campaign),
  'season': _season,
  'results':
      results ??
      [
        estimatedResult('validity_at_download'),
        insufficientResult('validity_at_download'),
      ],
  'may_be_outdated': true,
  'notice': farmerNotice,
  'storage': {
    'backup': 'EXCLUDED_FROM_PRIVATE_BACKUP',
    'discard_on': ['IDENTITY_CHANGE', 'SIGN_OUT'],
    'replace_only_with': 'NEWER_SAME_SUBJECT_AND_SCOPE',
  },
};

/// Cuerpo de `GET /estimation/results` (perfil FARMER).
Map<String, Object?> farmerResultsJson({
  String tenant = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
  String campaign = campaignWinter,
}) => {
  'contract_version': 1,
  'profile': 'FARMER',
  'scope': {'tenant_ref': tenant},
  'target': _target(campaign),
  'season': _season,
  'evaluated_at': '2026-11-02T22:05:00.000Z',
  'results': [estimatedResult('validity'), insufficientResult('validity')],
  'notice': farmerNotice,
};
