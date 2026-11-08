// Datos SINTÉTICOS compartidos por las pruebas de la evidencia de dictado
// (F09-VOZ-13, MOB #167). Ningún texto procede de un dictado real.
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/purchase/voice_purchase_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';

/// Frase sintética: sirve de marcador para buscarla en el archivo.
const marker = 'FRASE SINTETICA DE PRUEBA EVIDENCIA QX7';
const consentV1 = 'F09-EVID-CONSENT-PRUEBA-1';

const glifosato = CatalogEntry(
  id: 1,
  name: 'Glifosato',
  unit: CatalogUnit.liter,
);
const agroNorte = CatalogEntry(id: 7, name: 'Agro Norte');
const campaign = CatalogEntry(id: 3, name: 'Campaña de prueba');
const titular = CatalogEntry(id: 4, name: 'Titular sintético');

DateTime clockAt(int minute) => DateTime.utc(2026, 11, 8, 12, minute);

/// Borrador de compra como lo dejaría la voz: proveedor, producto y una
/// cantidad de 1 L (la «litro y medio» mal oída del POCO, §2.1), sin moneda.
VoicePurchaseDraft voiceProposal() => const VoicePurchaseDraft(
  campaign: DraftField.resolved(campaign, origin: FieldOrigin.preset),
  recipient: DraftField.resolved(titular, origin: FieldOrigin.preset),
  supplier: DraftField.resolved(agroNorte, origin: FieldOrigin.voice),
  lines: [
    VoicePurchaseLine(
      key: 1,
      product: DraftField.resolved(
        glifosato,
        origin: FieldOrigin.voice,
        heard: 'glifosato',
      ),
      quantity: DraftField.resolved(
        SpokenQuantity(1000, SpokenUnit.liter),
        origin: FieldOrigin.voice,
      ),
      price: DraftField.resolved(SpokenPrice(18000), origin: FieldOrigin.voice),
    ),
  ],
  nextLineKey: 2,
);

/// La persona corrige la cantidad (1,5 L) y completa la moneda a mano.
VoicePurchaseDraft corrected(VoicePurchaseDraft d) => d.updateLine(
  1,
  (line) => line.copyWith(
    quantity: const DraftField.resolved(
      SpokenQuantity(1500, SpokenUnit.liter),
      origin: FieldOrigin.manual,
    ),
    currency: const DraftField.resolved(
      CurrencyCode.bob,
      origin: FieldOrigin.manual,
    ),
  ),
);
