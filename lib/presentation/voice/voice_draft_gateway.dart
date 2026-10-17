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
import '../../domain/operation_mode.dart';
import '../../domain/person_roles.dart';
import '../../voice_draft/application/voice_application_draft.dart';
import '../../voice_draft/catalog/voice_catalog.dart';
import '../../voice_draft/plan/voice_plan_draft.dart';
import '../../voice_draft/purchase/voice_purchase_draft.dart';
import '../../voice_draft/text/units.dart';

final voiceDraftGatewayProvider = Provider<VoiceDraftGateway>(
  (ref) => VoiceDraftGateway(ref.watch(repositoryProvider)),
);

class VoiceDraftGateway {
  VoiceDraftGateway(this._repo, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AgroRepository _repo;

  /// Reloj de la confirmación: el mismo `DateTime.now()` que usan los
  /// formularios al enviar. Las pruebas lo fijan.
  final DateTime Function() _clock;

  /// Catálogos para un borrador de compra.
  Future<VoiceCatalog> purchaseCatalog() async {
    final suppliers = await _repo.suppliers();
    final people = await _repo.peopleFor(PersonPurpose.purchaseAllocation);
    final campaign = await _repo.activeCampaign();
    return VoiceCatalog(
      products: await _products(),
      suppliers: [for (final row in suppliers) _entry(row)],
      people: [for (final row in people) _entry(row)],
      activeCampaign: campaign == null ? null : _entry(campaign),
    );
  }

  /// Registra la compra con el caso de uso del formulario manual.
  Future<int> confirmPurchase(VoicePurchaseDraft draft) =>
      _repo.confirmPurchase(draft.toDomain(at: _clock()));

  /// Catálogos para un borrador de planificación. En PERSONAL sólo se ofrecen
  /// los chacos del titular; el repositorio vuelve a comprobarlo al escribir.
  Future<VoiceCatalog> planCatalog() async {
    final context = await _repo.operatingContext();
    final farms = await _repo.farms();
    final campaign = await _repo.activeCampaign();
    return VoiceCatalog(
      products: await _products(),
      farms: [
        for (final row in farms)
          if (context.mode != OperationMode.personal ||
              row['owner_person_id'] == context.ownerPersonId)
            CatalogEntry(
              id: row['id']! as int,
              name: row['name']! as String,
              areaM2: row['area_m2'] as int?,
            ),
      ],
      activeCampaign: campaign == null ? null : _entry(campaign),
    );
  }

  /// Crea el plan con el caso de uso del formulario de planificación.
  Future<int> confirmPlan(VoicePlanDraft draft) {
    final plan = draft.toDomain();
    return _repo.addPlanMulti(
      farmId: plan.farmId,
      campaignId: plan.campaignId,
      areaM2: plan.areaM2,
      items: plan.items,
    );
  }

  /// Catálogos para un borrador de aplicación, con el mismo filtro que el
  /// formulario: personas que pueden aplicar (`peopleFor(applicator)`) y sólo
  /// los chacos cuyo dueño puede aplicar. El dueño del chaco es quien aplica.
  Future<VoiceCatalog> applicationCatalog() async {
    final people = await _repo.peopleFor(PersonPurpose.applicator);
    final applicators = {for (final p in people) p['id']! as int: _entry(p)};
    final farms = [
      for (final farm in await _repo.farms())
        if (applicators.containsKey(farm['owner_person_id'])) farm,
    ];
    final campaign = await _repo.activeCampaign();
    return VoiceCatalog(
      products: await _products(),
      farms: [
        for (final row in farms)
          CatalogEntry(
            id: row['id']! as int,
            name: row['name']! as String,
            areaM2: row['area_m2'] as int?,
          ),
      ],
      people: applicators.values.toList(growable: false),
      farmOwners: {
        for (final row in farms)
          row['id']! as int: applicators[row['owner_person_id']]!,
      },
      activeCampaign: campaign == null ? null : _entry(campaign),
    );
  }

  /// Stock disponible de [personId] por producto, en unidad base. Sólo
  /// lectura: es la proyección que se muestra antes de confirmar.
  Future<Map<int, int>> availableStock(int personId) async => {
    for (final row in await _repo.availableProductsForOwner(personId))
      row['product_id']! as int: row['available_base']! as int,
  };

  /// Registra la aplicación con `confirmApplication()`, la autoridad de FIFO,
  /// costo, movimientos y stock, como el formulario.
  Future<int> confirmApplication(VoiceApplicationDraft draft) =>
      _repo.confirmApplication(draft.toDomain(at: _clock()));

  Future<List<CatalogEntry>> _products() async => [
    for (final row in await _repo.products())
      CatalogEntry(
        id: row['id']! as int,
        name: row['name']! as String,
        unit: CatalogUnit.fromCode(row['unit'] as String?),
      ),
  ];

  static CatalogEntry _entry(Map<String, Object?> row) =>
      CatalogEntry(id: row['id']! as int, name: row['name']! as String);
}
