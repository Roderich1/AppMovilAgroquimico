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

  /// Catálogos para un borrador de compra, con la misma lectura que el
  /// formulario (`peopleAndContextFor(purchaseAllocation)`): personas,
  /// modalidad y titular en una consulta. En inventario propio la compra es
  /// del titular, sin elegir persona.
  Future<VoiceCatalog> purchaseCatalog() async {
    final suppliers = await _repo.suppliers();
    final read = await _repo.peopleAndContextFor(
      PersonPurpose.purchaseAllocation,
    );
    final campaign = await _repo.activeCampaign();
    final people = [for (final row in read.people) _entry(row)];
    final owner = read.context.mode == OperationMode.personal
        ? people.where((p) => p.id == read.context.ownerPersonId).firstOrNull
        : null;
    return VoiceCatalog(
      products: await _products(),
      suppliers: [for (final row in suppliers) _entry(row)],
      people: owner == null ? people : [owner],
      activeCampaign: campaign == null ? null : _entry(campaign),
      loadedMode: read.context.mode,
      personalOwner: owner,
    );
  }

  /// Registra la compra con el caso de uso del formulario manual.
  Future<int> confirmPurchase(VoicePurchaseDraft draft) =>
      _repo.confirmPurchase(draft.toDomain(at: _clock()));

  /// Catálogos para un borrador de planificación, con la misma lectura que
  /// el formulario (`farmsAndContext`): en propio sólo los chacos del
  /// titular. El repositorio vuelve a comprobarlo al escribir.
  Future<VoiceCatalog> planCatalog() async {
    final read = await _repo.farmsAndContext();
    final campaign = await _repo.activeCampaign();
    return VoiceCatalog(
      products: await _products(),
      farms: [
        for (final row in read.farms)
          CatalogEntry(
            id: row['id']! as int,
            name: row['name']! as String,
            areaM2: row['area_m2'] as int?,
          ),
      ],
      activeCampaign: campaign == null ? null : _entry(campaign),
      loadedMode: read.context.mode,
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
    final read = await _repo.peopleAndContextFor(PersonPurpose.applicator);
    final people = read.people;
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
      loadedMode: read.context.mode,
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
