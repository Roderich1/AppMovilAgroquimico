/// Catálogos existentes, en memoria, para resolver lo dictado (EVO-010).
///
/// Es una fotografía de sólo lectura que entrega la capa de presentación. El
/// borrador no consulta la base ni crea nada: un nombre que no está en el
/// catálogo queda **faltante** y bloquea la confirmación (decisión pendiente
/// D-F09-2: sin «Crear nuevo» desde la voz).
library;

import '../../domain/operation_mode.dart';
import '../text/normalize.dart';
import '../text/units.dart';

/// Una entrada de catálogo: producto, proveedor, chaco, campaña o persona.
final class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.name,
    this.unit,
    this.areaM2,
  });

  final int id;
  final String name;

  /// Sólo productos: unidad del catálogo.
  final CatalogUnit? unit;

  /// Sólo chacos: superficie registrada, en m².
  final int? areaM2;

  @override
  bool operator ==(Object other) =>
      other is CatalogEntry && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'CatalogEntry($id)';
}

/// Una línea de un plan pendiente: producto, dosis y cantidad requerida,
/// tal como las guardó `addPlanMulti`.
final class PendingPlanItem {
  const PendingPlanItem({
    required this.product,
    required this.doseBasePerHa,
    required this.requiredBase,
  });

  final CatalogEntry product;
  final int doseBasePerHa;
  final int requiredBase;
}

/// Un plan pendiente de la campaña activa (D-F09-4). Sólo se ofrece para su
/// chaco y nunca se elige solo: el usuario lo selecciona.
final class PendingPlan {
  const PendingPlan({
    required this.id,
    required this.campaignId,
    required this.farmId,
    required this.areaM2,
    required this.items,
    this.plannedDate,
  });

  final int id;
  final int campaignId;
  final int farmId;
  final int areaM2;
  final List<PendingPlanItem> items;
  final String? plannedDate;

  /// Para elegirlo en la pantalla.
  CatalogEntry get entry => CatalogEntry(
    id: id,
    name:
        'Plan n.º $id · ${plannedDate ?? 'sin fecha'} · '
        '${items.map((i) => i.product.name).join(', ')}',
  );
}

/// Catálogos vigentes al abrir el borrador.
final class VoiceCatalog {
  const VoiceCatalog({
    this.products = const [],
    this.suppliers = const [],
    this.farms = const [],
    this.people = const [],
    this.activeCampaign,
    this.farmOwners = const {},
    this.loadedMode,
    this.personalOwner,
    this.pendingPlans = const [],
  });

  final List<CatalogEntry> products;
  final List<CatalogEntry> suppliers;

  /// Chacos activos que la modalidad permite usar.
  final List<CatalogEntry> farms;

  /// Personas elegibles para el propósito del borrador (por ejemplo, recibir
  /// una compra), ya filtradas por modalidad y titular.
  final List<CatalogEntry> people;

  /// Campaña activa, si hay. El borrador la propone y la muestra.
  final CatalogEntry? activeCampaign;

  /// Dueño de cada chaco (por id del chaco), sólo si puede aplicar. Como en el
  /// formulario de aplicación, el dueño del chaco es quien aplica y de su
  /// inventario sale el producto.
  final Map<int, CatalogEntry> farmOwners;

  /// Modalidad con que se leyeron estas opciones (#26). Si la vigente cambia
  /// con la pantalla abierta, el borrador no se puede confirmar: hay que
  /// volver a abrirla, como los formularios (`modeChangedSince`).
  final OperationMode? loadedMode;

  /// En inventario propio, el titular: la compra se le asigna sin elegir
  /// persona, como en el formulario. `null` en compartido.
  final CatalogEntry? personalOwner;

  /// Planes pendientes de la campaña activa en chacos que se pueden usar.
  final List<PendingPlan> pendingPlans;

  /// Planes pendientes de [farmId] en [campaignId] (la campaña del
  /// borrador). Un plan de otro chaco o de otra campaña no se ofrece.
  List<PendingPlan> plansFor(int farmId, int? campaignId) => [
    for (final plan in pendingPlans)
      if (plan.farmId == farmId && plan.campaignId == campaignId) plan,
  ];
}

enum ResolutionState { resolved, ambiguous, missing }

/// Resultado de buscar un nombre dictado en un catálogo.
final class Resolution {
  const Resolution._(this.state, this.heard, this.entry, this.candidates);

  final ResolutionState state;

  /// Lo oído, tal cual se transcribió.
  final String heard;

  /// Sólo si [state] es [ResolutionState.resolved].
  final CatalogEntry? entry;

  /// Opciones para elegir cuando [state] es [ResolutionState.ambiguous].
  final List<CatalogEntry> candidates;
}

/// Busca [heard] en [entries].
///
/// - **Resuelto** sólo si exactamente una entrada coincide con la forma
///   canónica (sin tildes, mayúsculas ni guiones, y con los números como
///   cifra): «germi cien» encuentra «Germi-100».
/// - **Ambiguo** si varias entradas coinciden exactamente (homónimos) o si hay
///   coincidencias aproximadas. Una aproximación nunca se elige sola, aunque
///   sea la única (ADR-003: no autoelegir entidades críticas ni usar una
///   puntuación como validación).
/// - **Faltante** si no hay nada parecido.
Resolution resolveName(String heard, List<CatalogEntry> entries) {
  final target = canonicalTokens(heard);
  if (target.isEmpty) {
    return Resolution._(ResolutionState.missing, heard, null, const []);
  }
  final key = target.join(' ');
  final exact = [
    for (final entry in entries)
      if (canonicalName(entry.name) == key) entry,
  ];
  if (exact.length == 1) {
    return Resolution._(
      ResolutionState.resolved,
      heard,
      exact.single,
      const [],
    );
  }
  if (exact.length > 1) {
    return Resolution._(ResolutionState.ambiguous, heard, null, exact);
  }
  final near = [
    for (final entry in entries)
      if (_similar(target, canonicalTokens(entry.name))) entry,
  ];
  if (near.isEmpty) {
    return Resolution._(ResolutionState.missing, heard, null, const []);
  }
  return Resolution._(
    ResolutionState.ambiguous,
    heard,
    null,
    near.take(6).toList(growable: false),
  );
}

/// Parecido suficiente para **proponer** una opción, nunca para elegirla:
/// todas las palabras dichas aparecen en el nombre (o al revés), cada una igual
/// o a una distancia de edición pequeña.
bool _similar(List<String> heard, List<String> name) {
  if (name.isEmpty) return false;
  bool covers(List<String> a, List<String> b) =>
      a.every((word) => b.any((other) => _close(word, other)));
  return covers(heard, name) || covers(name, heard);
}

bool _close(String a, String b) {
  if (a == b) return true;
  final shorter = a.length < b.length ? a.length : b.length;
  if (shorter < 4) return false;
  final limit = shorter >= 8 ? 2 : 1;
  return _distance(a, b, limit) <= limit;
}

/// Distancia de Levenshtein con corte temprano.
int _distance(String a, String b, int limit) {
  if ((a.length - b.length).abs() > limit) return limit + 1;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    var rowMin = current[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final value = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
      current[j] = value;
      if (value < rowMin) rowMin = value;
    }
    if (rowMin > limit) return limit + 1;
    previous = current;
  }
  return previous[b.length];
}
