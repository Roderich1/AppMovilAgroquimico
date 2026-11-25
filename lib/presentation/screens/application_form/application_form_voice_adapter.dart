import 'dart:async' show unawaited;

import '../../../voice/session/voice_session_state.dart';
import '../../../voice_draft/application/application_interpreter.dart';
import '../../../voice_draft/application/voice_application_draft.dart';
import '../../../voice_draft/catalog/voice_catalog.dart';
import '../../../voice_draft/core/draft_field.dart';
import '../../../voice_draft/core/numeric_review.dart';
import '../../../voice_draft/interpretation/voice_intent.dart';
import '../../../voice_draft/text/units.dart';
import '../../../voice_evidence/draft_snapshot.dart'
    show formCatalogEntry, formDraftField;
import '../../voice/voice_draft_widgets.dart' show voiceVocabularyHints;
import '../../voice/voice_form_dictation.dart';
import '../../widgets/common.dart';
import 'application_form_notifier.dart';
import 'application_form_state.dart';

/// «Completar por voz» en «Nueva aplicación» (F09, formulario único).
class ApplicationFormVoiceAdapter
    implements VoiceFormTarget<VoiceApplicationDraft> {
  ApplicationFormVoiceAdapter({
    required this.readState,
    required this.readNotifier,
    required this.readVoice,
    required this.loadVoiceCatalog,
    required this.onApplied,
    required this.onOpenPlan,
  });

  final ApplicationFormState Function() readState;
  final ApplicationFormNotifier Function() readNotifier;
  final VoiceFormDictation<VoiceApplicationDraft>? Function() readVoice;
  final Future<VoiceCatalog> Function() loadVoiceCatalog;
  final void Function(
    VoiceApplicationDraft shadow,
    String text,
    Map<int, int> lineIds,
  )
  onApplied;
  final Future<void> Function(int planId) onOpenPlan;

  VoiceCatalog? catalog;
  final List<String> _notices = [];
  int _seenDisagreements = 0;

  Future<void> loadCatalog() async {
    final next = await loadVoiceCatalog();
    catalog = next;
    readVoice()?.session.setVocabularyHints(voiceVocabularyHints(next));
  }

  static Object? areaCanon(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final v = tryParseDecimal(t);
    return v == null ? 'texto:$t' : (v * 10000).round();
  }

  @override
  FormSnapshot snapshot() {
    final state = readState();
    return FormSnapshot(
      header: {
        'farm': state.farmId,
        'area': areaCanon(state.areaText),
        'plan': null,
      },
      lines: [
        for (final l in state.lines)
          LineSnapshot(l.id, {
            'product': l.product['product_id'],
            'quantity': l.quantityBase > 0 ? l.quantityBase : null,
          }),
      ],
    );
  }

  @override
  int nextLineId() => readState().nextLineId;

  VoiceApplicationDraft evidenceDraft() {
    final c = catalog!;
    final state = readState();
    final area = areaCanon(state.areaText);
    return VoiceApplicationDraft(
      campaign: formDraftField(c.activeCampaign),
      farm: formDraftField(formCatalogEntry(c.farms, state.farmId)),
      person: formCatalogEntry([
        ...c.people,
        ...c.farmOwners.values,
      ], state.personId),
      area: formDraftField(area is int ? area : null),
      lines: [for (final l in state.lines) _evidenceLine(l, c)],
      nextLineKey: state.nextLineId,
    );
  }

  static VoiceApplicationLine _evidenceLine(
    ApplicationLineData l,
    VoiceCatalog c,
  ) {
    final product = formCatalogEntry(c.products, l.product['product_id']);
    return VoiceApplicationLine(
      key: l.id,
      product: formDraftField(product),
      quantity: formDraftField(
        l.quantityBase > 0
            ? SpokenAmount(
                l.quantityBase,
                product?.unit == CatalogUnit.kilogram
                    ? SpokenUnit.kilogram
                    : SpokenUnit.liter,
              )
            : null,
      ),
    );
  }

  @override
  VoiceApplicationDraft? startShadow() {
    final c = catalog;
    if (c == null) return null;
    _notices.clear();
    _seenDisagreements =
        readVoice()?.session.snapshot.numericDisagreements ?? 0;
    return VoiceApplicationDraft.start(c);
  }

  @override
  VoiceApplicationDraft interpret(
    VoiceApplicationDraft shadow,
    String text,
    VoiceSessionSnapshot session,
  ) {
    final r = interpretApplication(text, shadow, catalog!);
    if (r.otherIntent != null) _notices.add(_otherIntent(r.otherIntent!));
    var next = r.draft;
    if (session.numericDisagreements > _seenDisagreements) {
      _seenDisagreements = session.numericDisagreements;
      next = reviewApplicationNumbers(shadow, next, numericDisagreementMessage);
    }
    return next;
  }

  static String _otherIntent(VoiceIntent intent) => switch (intent) {
    VoiceIntent.unsupported =>
      'Los pagos y las consultas por voz no están disponibles. No se cambió '
          'la aplicación.',
    VoiceIntent.ambiguous =>
      'La frase mezcla varias operaciones. No se cambió la aplicación: dicte '
          'sólo la aplicación.',
    _ =>
      'Eso parece otra operación. No se cambió la aplicación: regístrela '
          'desde su propia pantalla.',
  };

  @override
  VoiceProposal propose(VoiceApplicationDraft shadow, FormSnapshot now) {
    final header = <String, ProposedValue>{};
    final c = catalog!;
    final state = readState();
    var farmFromVoice = false;
    if (state.planId == null) {
      final farm = _entry(
        shadow.farm,
        notInCatalog: (heard) =>
            '«$heard» no está entre los chacos de quienes aplican. Elija uno '
            'existente o créelo desde el selector; la voz no crea nada nuevo.',
      );
      if (farm != null) {
        farmFromVoice = farm.value != null;
        final owner = farm.value == null ? null : c.farmOwners[farm.value];
        final personSet = state.personId != null && !state.personalMode;
        if (owner != null && personSet && owner.id != state.personId) {
          header['farm'] = ProposedValue(
            null,
            display: farm.display,
            review: VoiceReview(
              'El chaco «${farm.display}» es de ${owner.name}. Elegirlo cambia '
              'la persona y quita los productos de la mezcla.',
              options: [ReviewOption('Usar «${farm.display}»', farm.value)],
            ),
          );
        } else {
          header['farm'] = farm;
        }
      }
      final area = shadow.area;
      final m2 = area.value;
      final fromFarm = area.origin == FieldOrigin.preset;
      if (m2 != null && !area.isManual && (!fromFarm || farmFromVoice)) {
        final display = '${formatForInput(m2 / 10000, maxDecimals: 4)} ha';
        header['area'] = area.isResolved && !area.review
            ? ProposedValue(m2, display: display)
            : ProposedValue(
                null,
                display: display,
                review: VoiceReview(
                  area.message ?? 'Confirme el área.',
                  options: [ReviewOption('Usar $display', m2)],
                ),
              );
      }
      final plan = shadow.plan;
      if (plan != null) {
        header['plan'] = ProposedValue(
          null,
          display: 'plan',
          review: VoiceReview(
            plan.candidates.isEmpty
                ? (plan.message ??
                      'No hay planes pendientes para ese chaco en la campaña '
                          'activa.')
                : 'Elija el plan pendiente que se aplica. Se abre con sus '
                      'productos y cantidades previstas.',
            options: [
              for (final p in plan.candidates) ReviewOption(p.name, p.id),
            ],
          ),
        );
      }
    }
    final lines = <ProposedLine>[];
    for (final line in shadow.lines) {
      final fields = <String, ProposedValue>{};
      final product = _entry(
        line.product,
        notInCatalog: (heard) =>
            '«$heard» no está en el catálogo. Elija un producto con '
            'existencias; la voz no crea nada nuevo.',
      );
      if (product != null) fields['product'] = product;
      final quantity = _quantity(line);
      if (quantity != null) fields['quantity'] = quantity;
      if (fields.isNotEmpty) lines.add(ProposedLine(fields, source: line.key));
    }
    return VoiceProposal(header: header, lines: lines, notices: [..._notices]);
  }

  static ProposedValue? _entry(
    DraftField<CatalogEntry> field, {
    required String Function(String heard) notInCatalog,
  }) {
    if (field.origin == FieldOrigin.preset || field.isManual) return null;
    switch (field.status) {
      case FieldStatus.resolved:
        final e = field.value!;
        return field.review
            ? ProposedValue(
                null,
                display: e.name,
                review: VoiceReview(
                  field.message ?? 'Confirme «${e.name}».',
                  options: [ReviewOption('Usar ${e.name}', e.id)],
                ),
              )
            : ProposedValue(e.id, display: e.name);
      case FieldStatus.ambiguous:
        return ProposedValue(
          null,
          display: field.heard ?? '',
          review: VoiceReview(
            field.message ?? 'Hay varias opciones: elija una.',
            options: [
              for (final c in field.candidates) ReviewOption(c.name, c.id),
            ],
          ),
        );
      case FieldStatus.missing || FieldStatus.invalid:
        final heard = field.heard?.trim() ?? '';
        if (heard.isEmpty) return null;
        return ProposedValue(
          null,
          display: heard,
          review: VoiceReview(notInCatalog(heard)),
        );
    }
  }

  ProposedValue? _quantity(VoiceApplicationLine line) {
    final f = line.quantity;
    final q = f.value;
    if (q == null) return null;
    final unitName = switch (q.unit) {
      SpokenUnit.liter => 'L',
      SpokenUnit.milliliter => 'mL',
      SpokenUnit.kilogram => 'kg',
      SpokenUnit.gram => 'g',
    };
    final display = '${formatForInput(q.thousandths / 1000)} $unitName';
    final base = q.unit.toBase(q.thousandths);
    final unit = line.product.value?.unit;
    if (base == null || base <= 0) {
      return ProposedValue(
        null,
        display: display,
        review: const VoiceReview(
          'La cantidad dicha no es un número entero de mililitros o gramos: '
          'escríbala al editar la línea.',
        ),
      );
    }
    if (unit != null && q.unit.family != unit) {
      return ProposedValue(
        null,
        display: display,
        review: VoiceReview(
          'La unidad dicha ($display) no corresponde al producto, que se mide '
          'en ${unit == CatalogUnit.liter ? 'litros' : 'kilos'}: corrija la '
          'cantidad al editar la línea.',
        ),
      );
    }
    if (!f.isResolved || f.review) {
      return ProposedValue(
        null,
        display: display,
        review: VoiceReview(
          f.message ?? 'Confirme la cantidad.',
          options: [ReviewOption('Usar $display', base)],
        ),
      );
    }
    return ProposedValue(base, display: display);
  }

  @override
  void applyPlan(MergePlan plan) {
    readNotifier().applyVoicePlan(plan);
  }

  @override
  void applyUndo(UndoPlan plan) {
    readNotifier().applyVoiceUndo(plan);
  }

  @override
  void setSlot(SlotRef slot, Object? value) {
    if (slot.line == null && slot.field == 'plan') {
      if (value is int) {
        unawaited(onOpenPlan(value));
      }
      return;
    }
    readNotifier().setVoiceSlot(slot, value);
  }

  @override
  String describeSlot(SlotRef slot) {
    if (slot.line == null) {
      return switch (slot.field) {
        'farm' => 'chaco',
        'area' => 'área',
        _ => 'plan',
      };
    }
    final index = readState().lines.indexWhere((l) => l.id == slot.line);
    return 'producto ${index + 1}: '
        '${slot.field == 'quantity' ? 'cantidad' : 'producto'}';
  }

  @override
  void onDictationApplied(
    VoiceApplicationDraft shadow,
    String text,
    Map<int, int> lineIds,
  ) => onApplied(shadow, text, lineIds);
}
