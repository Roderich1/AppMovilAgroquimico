/// Lectura de los borradores de voz para la evidencia (F09-VOZ-13, #167).
///
/// Sólo **lee** los tipos de `lib/voice_draft/` (propiedad de la sesión B):
/// los aplana en campos serializables y calcula las correcciones entre lo
/// que propuso la voz y lo que quedó. No modifica ningún borrador ni
/// participa en la confirmación.
library;

import '../domain/models.dart';
import '../voice_draft/application/voice_application_draft.dart';
import '../voice_draft/catalog/voice_catalog.dart';
import '../voice_draft/core/draft_field.dart';
import '../voice_draft/plan/voice_plan_draft.dart';
import '../voice_draft/purchase/voice_purchase_draft.dart';
import '../voice_draft/text/units.dart';
import 'voice_evidence.dart';

/// Operación de un borrador, o error si el tipo no es uno de los tres.
VoiceEvidenceKind evidenceKindOf(Object draft) => switch (draft) {
  VoicePurchaseDraft() => VoiceEvidenceKind.purchase,
  VoiceApplicationDraft() => VoiceEvidenceKind.application,
  VoicePlanDraft() => VoiceEvidenceKind.plan,
  _ => throw ArgumentError.value(
    draft.runtimeType,
    'draft',
    'no es un borrador de voz',
  ),
};

/// Todos los campos del borrador, en un orden estable.
List<EvidenceField> snapshotDraft(Object draft) => switch (draft) {
  VoicePurchaseDraft() => _purchase(draft),
  VoiceApplicationDraft() => _application(draft),
  VoicePlanDraft() => _plan(draft),
  _ => throw ArgumentError.value(
    draft.runtimeType,
    'draft',
    'no es un borrador de voz',
  ),
};

List<EvidenceField> _purchase(VoicePurchaseDraft d) => [
  _field('supplier', d.supplier),
  _field('campaign', d.campaign),
  _field('recipient', d.recipient),
  _field('exchangeRate', d.exchangeRate),
  for (final line in d.lines) ...[
    _field('line[${line.key}].product', line.product),
    _field('line[${line.key}].quantity', line.quantity),
    _field('line[${line.key}].price', line.price),
    _field('line[${line.key}].currency', line.currency),
  ],
];

List<EvidenceField> _application(VoiceApplicationDraft d) => [
  _field('campaign', d.campaign),
  _field('farm', d.farm),
  if (d.person != null) _derived('person', d.person),
  _field('area', d.area),
  if (d.plan != null) _field('plan', d.plan!),
  for (final line in d.lines) ...[
    _field('line[${line.key}].product', line.product),
    _field('line[${line.key}].quantity', line.quantity),
    if (line.plannedBase != null)
      _derived('line[${line.key}].plannedBase', line.plannedBase),
    if (line.doseBasePerHa != null)
      _derived('line[${line.key}].doseBasePerHa', line.doseBasePerHa),
  ],
];

List<EvidenceField> _plan(VoicePlanDraft d) => [
  _field('campaign', d.campaign),
  _field('farm', d.farm),
  _field('area', d.area),
  for (final line in d.lines) ...[
    _field('line[${line.key}].product', line.product),
    _field('line[${line.key}].dose', line.dose),
  ],
];

EvidenceField _field(String path, DraftField<Object?> f) => EvidenceField(
  path: path,
  status: f.status.name,
  origin: f.origin?.name,
  value: encodeEvidenceValue(f.value),
  heard: f.heard,
  candidates: [for (final c in f.candidates) _entry(c)],
);

EvidenceField _derived(String path, Object? value) => EvidenceField(
  path: path,
  status: FieldStatus.resolved.name,
  origin: 'derived',
  value: encodeEvidenceValue(value),
);

Map<String, Object?> _entry(CatalogEntry e) => {
  'id': e.id,
  'name': e.name,
  if (e.unit != null) 'unit': e.unit!.code,
  if (e.areaM2 != null) 'areaM2': e.areaM2,
};

/// Valor de un campo en forma JSON. Las cantidades se guardan como se
/// dijeron (milésimas y unidad dicha); la conversión a la unidad base es
/// cosa del cálculo de la evaluación (equivalencias de D3).
Object? encodeEvidenceValue(Object? value) => switch (value) {
  null => null,
  int() || String() || bool() => value,
  CatalogEntry() => _entry(value),
  SpokenQuantity() => {
    'thousandths': value.thousandths,
    'unit': value.unit.name,
  },
  SpokenAmount() => {'thousandths': value.thousandths, 'unit': value.unit.name},
  SpokenDose() => {
    'thousandthsPerHa': value.thousandthsPerHa,
    'unit': value.unit.name,
  },
  SpokenPrice() => {
    'minorPerUnit': value.minorPerUnit,
    if (value.perUnit != null) 'perUnit': value.perUnit!.code,
  },
  CurrencyCode() => value.name,
  // Un tipo nuevo no se convierte en texto libre: se deja constancia de que
  // no se supo guardar.
  _ => {'unsupported': value.runtimeType.toString()},
};

/// Correcciones entre lo propuesto por la voz y el borrador final.
///
/// - un campo propuesto que cambió de estado o valor: [CorrectionKind.changed];
/// - uno que la voz no propuso y quedó resuelto: [CorrectionKind.added];
/// - uno propuesto que ya no está (línea quitada): [CorrectionKind.removed];
/// - uno con origen manual y el mismo valor: [CorrectionKind.reaffirmed];
/// - uno **confirmado** con el mismo valor, aunque antes estuviera por
///   revisar o ambiguo: [CorrectionKind.reaffirmed], nunca «cambiado».
///
/// Un campo que la voz no propuso y quedó como lo puso el sistema (por
/// ejemplo, la campaña activa) no es una corrección.
List<EvidenceCorrection> diffEvidenceFields(
  List<EvidenceField> proposed,
  List<EvidenceField> finalFields,
) {
  final byPath = {for (final f in proposed) f.path: f};
  final finalPaths = <String>{};
  final out = <EvidenceCorrection>[];
  for (final after in finalFields) {
    finalPaths.add(after.path);
    final before = byPath[after.path];
    // Dar por bueno el valor propuesto, sin cambiarlo, no es un cambio (POCO
    // 2026-11-08): se anota como «reafirmado», igual que elegir a mano la
    // misma opción, aunque el campo pasara de «por revisar» o ambiguo a
    // resuelto.
    if (before != null &&
        after.origin == FieldOrigin.confirmed.name &&
        _sameValue(before, after)) {
      out.add(
        EvidenceCorrection(
          path: after.path,
          kind: CorrectionKind.reaffirmed,
          proposed: before,
          finalField: after,
        ),
      );
      continue;
    }
    if (before == null) {
      if (after.origin == FieldOrigin.manual.name &&
          after.status != FieldStatus.missing.name) {
        out.add(
          EvidenceCorrection(
            path: after.path,
            kind: CorrectionKind.added,
            finalField: after,
          ),
        );
      }
      continue;
    }
    if (!before.sameContentAs(after)) {
      out.add(
        EvidenceCorrection(
          path: after.path,
          kind: CorrectionKind.changed,
          proposed: before,
          finalField: after,
        ),
      );
    } else if (after.origin == FieldOrigin.manual.name &&
        before.origin != FieldOrigin.manual.name) {
      out.add(
        EvidenceCorrection(
          path: after.path,
          kind: CorrectionKind.reaffirmed,
          proposed: before,
          finalField: after,
        ),
      );
    }
  }
  for (final before in proposed) {
    if (!finalPaths.contains(before.path)) {
      out.add(
        EvidenceCorrection(
          path: before.path,
          kind: CorrectionKind.removed,
          proposed: before,
        ),
      );
    }
  }
  return out;
}

/// Mismo valor, sin mirar el estado ni el origen.
bool _sameValue(EvidenceField before, EvidenceField after) => EvidenceField(
  path: after.path,
  status: before.status,
  value: after.value,
).sameContentAs(before);

/// Campo de un borrador armado con lo que tiene el formulario (formulario
/// único, F09): resuelto «a mano» si hay valor; faltante si no.
DraftField<T> formDraftField<T>(T? value) => value == null
    ? const DraftField.missing()
    : DraftField.resolved(value, origin: FieldOrigin.manual);

/// La entrada del catálogo con [id], para armar ese borrador; sin nombre si
/// ya no está en el catálogo cargado (la comparación es por id).
CatalogEntry? formCatalogEntry(Iterable<CatalogEntry> entries, Object? id) {
  if (id is! int) return null;
  return entries.where((e) => e.id == id).firstOrNull ??
      CatalogEntry(id: id, name: '');
}

/// Campos finales tomados del formulario (formulario único, F09), alineados
/// con lo propuesto por la voz para que [diffEvidenceFields] sólo anote lo
/// que de verdad cambió.
///
/// El formulario no sabe quién puso cada valor: el borrador final se arma
/// con todos sus valores como «manual» ([formDraftField]). Aquí, un campo
/// final con **el mismo valor** que el propuesto en esa ruta (mismo
/// producto, proveedor o chaco; misma cantidad en unidad base, aunque se
/// dijera en mL o g; mismo precio por unidad) se anota con el valor tal
/// como se dijo y con el origen de la propuesta; si la propuesta estaba por
/// revisar o era ambigua, como «confirmado» (reafirmado en las
/// correcciones). Un valor distinto queda como lo dejó la persona.
List<EvidenceField> alignFormFields(
  List<EvidenceField> proposed,
  List<EvidenceField> formFields,
) {
  final byPath = {for (final f in proposed) f.path: f};
  return [
    for (final after in formFields)
      switch (byPath[after.path]) {
        final before?
            when before.value != null &&
                after.value != null &&
                after.status == FieldStatus.resolved.name &&
                _sameCanonical(before.value, after.value) =>
          EvidenceField(
            path: after.path,
            status: FieldStatus.resolved.name,
            origin: before.status == FieldStatus.resolved.name
                ? before.origin
                : FieldOrigin.confirmed.name,
            value: before.value,
            heard: before.heard,
          ),
        _ => after,
      },
  ];
}

/// Igualdad de dos valores ya codificados ([encodeEvidenceValue]) en su
/// forma canónica: entradas del catálogo por id, cantidades y dosis en
/// unidad base, precios por centavos por unidad.
bool _sameCanonical(Object? a, Object? b) {
  final ca = _canonical(a);
  final cb = _canonical(b);
  if (ca is Map || cb is Map) {
    return EvidenceField(
      path: '',
      status: '',
      value: ca,
    ).sameContentAs(EvidenceField(path: '', status: '', value: cb));
  }
  return ca == cb;
}

Object? _canonical(Object? value) {
  if (value is! Map) return value;
  if (value['id'] case final int id) return ('entry', id);
  final unit = SpokenUnit.values
      .where((u) => u.name == value['unit'])
      .firstOrNull;
  if (unit != null) {
    if (value['thousandths'] case final int t) {
      return ('quantity', unit.family, unit.toBase(t) ?? '$t ${unit.name}');
    }
    if (value['thousandthsPerHa'] case final int t) {
      return ('dose', unit.family, unit.toBase(t) ?? '$t ${unit.name}');
    }
  }
  if (value['minorPerUnit'] case final int minor) return ('price', minor);
  return value;
}

/// Lo que la pantalla anota durante un borrador de voz para entregar la
/// evidencia al terminar. No guarda nada por sí misma ni toca el borrador.
///
/// Uso (la coordinadora lo conecta):
/// 1. tras cada resultado de voz aplicado con `applyVoice`, llamar a
///    [voiceApplied] con el borrador resultante y el texto final dictado;
/// 2. al confirmar, descartar o fallar la escritura, llamar a [finish] con
///    el borrador final y entregar la entrada a `VoiceEvidenceSink.record`.
final class VoiceEvidenceTrace {
  VoiceEvidenceTrace({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final List<String> _transcripts = [];
  final Map<String, EvidenceField> _proposed = {};
  final List<String> _order = [];
  DateTime? _startedAt;
  VoiceEvidenceKind? _kind;

  /// Marca el comienzo del primer dictado. Si no se llama, se toma el
  /// momento del primer [voiceApplied].
  void dictationStarted() => _startedAt ??= _clock();

  /// Anota lo que propuso la voz: para cada campo del borrador que no puso
  /// la persona a mano, su valor tras este dictado. Un campo manual no es una
  /// propuesta de la voz y no se anota.
  ///
  /// Formulario único (F09): cada dictado tiene su propia sombra, con sus
  /// propias claves de línea. Con [lineKeys] (clave de la sombra → id de la
  /// línea del formulario a la que fue) las rutas de línea se anotan con el
  /// id del formulario, el mismo con que se arma el borrador final; una línea
  /// de la sombra que no llegó al formulario no se anota, y un campo que este
  /// dictado no oyó (faltante, sin nada oído) no borra lo que propuso un
  /// dictado anterior.
  void voiceApplied(
    Object draftAfterVoice, {
    String? transcript,
    Map<int, int>? lineKeys,
  }) {
    _startedAt ??= _clock();
    _kind ??= evidenceKindOf(draftAfterVoice);
    if (transcript != null) _transcripts.add(transcript);
    for (final raw in snapshotDraft(draftAfterVoice)) {
      // Lo puesto o confirmado por la persona no es propuesta de la voz.
      if (raw.origin == FieldOrigin.manual.name ||
          raw.origin == FieldOrigin.confirmed.name) {
        continue;
      }
      final field = lineKeys == null ? raw : _rekey(raw, lineKeys);
      if (field == null) continue;
      if (lineKeys != null &&
          field.status == FieldStatus.missing.name &&
          field.value == null &&
          field.heard == null &&
          _proposed.containsKey(field.path)) {
        continue;
      }
      if (!_proposed.containsKey(field.path)) _order.add(field.path);
      _proposed[field.path] = field;
    }
  }

  static final _linePath = RegExp(r'^line\[(\d+)\]\.(.+)$');

  /// [field] con la clave de línea del formulario, o `null` si su línea no
  /// llegó al formulario. Los campos de cabecera no cambian.
  static EvidenceField? _rekey(EvidenceField field, Map<int, int> lineKeys) {
    final m = _linePath.firstMatch(field.path);
    if (m == null) return field;
    final id = lineKeys[int.parse(m.group(1)!)];
    if (id == null) return null;
    return EvidenceField(
      path: 'line[$id].${m.group(2)}',
      status: field.status,
      origin: field.origin,
      value: field.value,
      heard: field.heard,
      candidates: field.candidates,
    );
  }

  /// `true` si hubo al menos un dictado aplicado.
  bool get hasVoice => _kind != null;

  /// Construye la entrada. [finalDraft] es el borrador al terminar: el que
  /// se confirmó, el que había al descartar o el que falló al escribir.
  ///
  /// Con [fromForm], [finalDraft] se armó con los valores del formulario
  /// único ([formDraftField]) y se alinea con lo propuesto
  /// ([alignFormFields]) antes de comparar.
  VoiceEvidenceEntry finish({
    required Object finalDraft,
    required VoiceEvidenceOutcome outcome,
    bool fromForm = false,
    String? sheetRef,
    String? engine,
    String? model,
    String? appCommit,
    int? firstPartialMs,
    int? finalMs,
  }) {
    final proposed = [for (final path in _order) _proposed[path]!];
    final finalFields = fromForm
        ? alignFormFields(proposed, snapshotDraft(finalDraft))
        : snapshotDraft(finalDraft);
    return VoiceEvidenceEntry(
      kind: _kind ?? evidenceKindOf(finalDraft),
      outcome: outcome,
      transcripts: List.unmodifiable(_transcripts),
      proposed: proposed,
      corrections: diffEvidenceFields(proposed, finalFields),
      confirmed: outcome == VoiceEvidenceOutcome.confirmed ? finalFields : null,
      sheetRef: sheetRef,
      engine: engine,
      model: model,
      appCommit: appCommit,
      firstPartialMs: firstPartialMs,
      finalMs: finalMs,
      dictationStartedAt: _startedAt,
    );
  }
}
