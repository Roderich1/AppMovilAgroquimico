/// Puente entre los borradores de voz y el dominio (F09).
///
/// Es el **único** sitio donde un borrador de voz llega al repositorio:
///
/// - lee los catálogos vigentes, ya filtrados por modalidad y titular con las
///   mismas consultas que usan los formularios (`peopleFor`), y
/// - confirma con el mismo caso de uso que el formulario manual, que vuelve a
///   aplicar dentro de su transacción las reglas de campaña activa, PERSONAL y
///   titular.
///
/// `lib/voice_draft/` no importa este archivo ni la base de datos.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/agro_repository.dart';
import '../../domain/person_roles.dart';
import '../../voice_draft/catalog/voice_catalog.dart';
import '../../voice_draft/purchase/voice_purchase_draft.dart';
import '../../voice_draft/text/units.dart';

final voiceDraftGatewayProvider = Provider<VoiceDraftGateway>(
  (ref) => VoiceDraftGateway(ref.watch(repositoryProvider)),
);

class VoiceDraftGateway {
  VoiceDraftGateway(this._repo);

  final AgroRepository _repo;

  /// Catálogos para un borrador de compra.
  Future<VoiceCatalog> purchaseCatalog() async {
    final products = await _repo.products();
    final suppliers = await _repo.suppliers();
    final people = await _repo.peopleFor(PersonPurpose.purchaseAllocation);
    final campaign = await _repo.activeCampaign();
    return VoiceCatalog(
      products: [
        for (final row in products)
          CatalogEntry(
            id: row['id']! as int,
            name: row['name']! as String,
            unit: CatalogUnit.fromCode(row['unit'] as String?),
          ),
      ],
      suppliers: [for (final row in suppliers) _entry(row)],
      people: [for (final row in people) _entry(row)],
      activeCampaign: campaign == null ? null : _entry(campaign),
    );
  }

  /// Registra la compra con el caso de uso del formulario manual.
  Future<int> confirmPurchase(VoicePurchaseDraft draft) =>
      _repo.confirmPurchase(draft.toDomain());

  static CatalogEntry _entry(Map<String, Object?> row) =>
      CatalogEntry(id: row['id']! as int, name: row['name']! as String);
}
