part of 'plan_form_screen.dart';

/// «Completar por voz» en «Nueva planificación» (F09, formulario único).
///
/// Motor de siempre para la planificación: Vosk por frases con revisión de
/// Whisper base (`speechPortFactoryProvider`) y la pista del catálogo. El
/// intérprete es `interpretPlan` sobre un borrador de voz propio de cada
/// dictado (acumula las frases: «dos litros por hectárea» [pausa] «de
/// Bellator» sigue funcionando).
///
/// Ranuras: cabecera `farm` (id) y `area` (m²); por línea `product` (id) y
/// `dose` (unidad base por hectárea). Un plan nunca toca inventario ni
/// cuentas: se guarda sólo con «Guardar planificación».
class _PlanVoice implements VoiceFormTarget<VoicePlanDraft> {
  _PlanVoice(this.s);

  final _PlanFormScreenState s;
  VoiceCatalog? catalog;
  final List<String> _notices = [];
  int _seenDisagreements = 0;
  int? _contextKey;

  void updateCatalog(_PlanCatalogs data) {
    catalog = VoiceCatalog(
      products: [
        for (final row in data.products)
          CatalogEntry(
            id: row['id']! as int,
            name: row['name']! as String,
            unit: CatalogUnit.fromCode(row['unit'] as String?),
          ),
      ],
      farms: [
        for (final row in data.farms)
          CatalogEntry(
            id: row['id']! as int,
            name: row['name']! as String,
            areaM2: row['area_m2'] as int?,
          ),
      ],
      activeCampaign: CatalogEntry(
        id: data.campaign['id']! as int,
        name: data.campaign['name']! as String,
      ),
      loadedMode: s.loadedMode,
    );
    s.voice?.session.setVocabularyHints(voiceVocabularyHints(catalog!));
  }

  @override
  FormSnapshot snapshot() => FormSnapshot(
    header: {'farm': s.farmId, 'area': _areaCanon(s.area.text)},
    lines: [for (final l in s.lines) LineSnapshot(l.id, l.voiceFields())],
  );

  static Object? _areaCanon(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final v = tryParseDecimal(t);
    return v == null ? 'texto:$t' : (v * 10000).round();
  }

  @override
  int nextLineId() => s._nextLineId;

  @override
  VoicePlanDraft startShadow() {
    _notices.clear();
    _seenDisagreements = s.voice?.session.snapshot.numericDisagreements ?? 0;
    _contextKey = null;
    var shadow = VoicePlanDraft.start(catalog!);
    // Contexto: la última línea con producto y sin dosis (para que «dos
    // litros por hectárea de X» la complete). El chaco NO se pasa como
    // contexto: un chaco dictado distinto del elegido debe preguntarse, no
    // descartarse en silencio.
    final last = s.lines.lastOrNull;
    final product = catalog!.products
        .where((p) => p.id == last?.product?['id'])
        .firstOrNull;
    if (last != null && product != null && last.voiceFields()['dose'] == null) {
      _contextKey = shadow.nextLineKey;
      shadow = shadow.addEmptyLine().updateLine(
        _contextKey!,
        (l) => l.copyWith(
          product: DraftField.resolved(product, origin: FieldOrigin.manual),
        ),
      );
    }
    return shadow;
  }

  @override
  VoicePlanDraft interpret(
    VoicePlanDraft shadow,
    String text,
    VoiceSessionSnapshot session,
  ) {
    final r = interpretPlan(text, shadow, catalog!);
    if (r.otherIntent != null) _notices.add(_otherIntent(r.otherIntent!));
    var next = r.draft;
    if (session.numericDisagreements > _seenDisagreements) {
      _seenDisagreements = session.numericDisagreements;
      next = reviewPlanNumbers(shadow, next, numericDisagreementMessage);
    }
    return next;
  }

  static String _otherIntent(VoiceIntent intent) => switch (intent) {
    VoiceIntent.unsupported =>
      'Los pagos y las consultas por voz no están disponibles. No se cambió '
          'la planificación.',
    VoiceIntent.ambiguous =>
      'La frase mezcla varias operaciones. No se cambió la planificación: '
          'dicte sólo el plan.',
    _ =>
      'Eso parece otra operación. No se cambió la planificación: regístrela '
          'desde su propia pantalla.',
  };

  @override
  VoiceProposal propose(VoicePlanDraft shadow, FormSnapshot now) {
    final header = <String, ProposedValue>{};
    if (!shadow.farm.isManual) {
      final farm = _entry(
        shadow.farm,
        notInCatalog: (heard) =>
            '«$heard» no está entre los chacos. Elija uno existente o créelo '
            'desde el selector; la voz no crea nada nuevo.',
      );
      if (farm != null) header['farm'] = farm;
    }
    final area = shadow.area;
    final m2 = area.value;
    // El área propuesta por un chaco elegido a mano ya la puso el formulario
    // al elegirlo: sólo cuenta la que se dictó o la del chaco dictado.
    final presetFromManualFarm =
        area.origin == FieldOrigin.preset && shadow.farm.isManual;
    if (m2 != null && !area.isManual && !presetFromManualFarm) {
      final display = '${formatForInput(m2 / 10000, maxDecimals: 2)} ha';
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
    final lines = <ProposedLine>[];
    for (final line in shadow.lines) {
      final fields = <String, ProposedValue>{};
      if (line.key != _contextKey) {
        final product = _entry(
          line.product,
          notInCatalog: (heard) =>
              '«$heard» no está en el catálogo. Elija uno existente o créelo '
              'desde el selector; la voz no crea nada nuevo.',
        );
        if (product != null) fields['product'] = product;
      }
      final dose = _dose(line);
      if (dose != null) fields['dose'] = dose;
      if (fields.isNotEmpty) lines.add(ProposedLine(fields));
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

  ProposedValue? _dose(VoicePlanLine line) {
    final f = line.dose;
    final d = f.value;
    if (d == null) return null;
    final unitName = switch (d.unit) {
      SpokenUnit.liter => 'L',
      SpokenUnit.milliliter => 'mL',
      SpokenUnit.kilogram => 'kg',
      SpokenUnit.gram => 'g',
    };
    final display =
        '${formatForInput(d.thousandthsPerHa / 1000)} $unitName por hectárea';
    final base = d.unit.toBase(d.thousandthsPerHa);
    final unit = line.product.value?.unit;
    if (base == null || base <= 0) {
      return ProposedValue(
        null,
        display: display,
        review: const VoiceReview(
          'La dosis dicha no es un número entero de mililitros o gramos por '
          'hectárea: escríbala en el campo.',
        ),
      );
    }
    if (unit != null && d.unit.family != unit) {
      return ProposedValue(
        null,
        display: display,
        review: VoiceReview(
          'La unidad dicha ($display) no corresponde al producto, que se mide '
          'en ${unit == CatalogUnit.liter ? 'litros' : 'kilos'}: escriba la '
          'dosis.',
        ),
      );
    }
    if (!f.isResolved || f.review) {
      return ProposedValue(
        null,
        display: display,
        review: VoiceReview(
          f.message ?? 'Confirme la dosis.',
          options: [ReviewOption('Usar $display', base)],
        ),
      );
    }
    return ProposedValue(base, display: display);
  }

  @override
  void applyPlan(MergePlan plan) {
    s._voiceSetState(() {
      for (final c in plan.changes) {
        _set(c.slot, c.after);
      }
      for (final n in plan.newLines) {
        final line = _PlanLine(n.line, null);
        if (n.line >= s._nextLineId) s._nextLineId = n.line + 1;
        s.lines.add(line);
        n.values.forEach((field, value) => _setLine(line, field, value));
      }
      if (!plan.changesNothing) s.dirty = true;
    });
  }

  @override
  void applyUndo(UndoPlan plan) {
    s._voiceSetState(() {
      for (final c in plan.restore) {
        _set(c.slot, c.after);
      }
      for (final id in plan.removeLines) {
        final line = s.lines.where((l) => l.id == id).firstOrNull;
        if (line == null) continue;
        s.lines.remove(line);
        line.dispose();
      }
    });
  }

  @override
  void setSlot(SlotRef slot, Object? value) {
    s._voiceSetState(() {
      _set(slot, value);
      s.dirty = true;
    });
  }

  void _set(SlotRef slot, Object? value) {
    if (slot.line == null) {
      switch (slot.field) {
        case 'farm':
          final farm = s._farms.where((f) => f['id'] == value).firstOrNull;
          // El chaco dictado no pisa un área ya escrita: el área tiene su
          // propia ranura (y su propia regla).
          s._selectFarmForVoice(farm);
        case 'area':
          s.area.text = value == null
              ? ''
              : formatForInput((value as int) / 10000, maxDecimals: 2);
      }
      return;
    }
    final line = s.lines.where((l) => l.id == slot.line).firstOrNull;
    if (line != null) _setLine(line, slot.field, value);
  }

  void _setLine(_PlanLine line, String field, Object? value) {
    switch (field) {
      case 'product':
        line.product = s._products.where((p) => p['id'] == value).firstOrNull;
      case 'dose':
        line.dose.text = value == null
            ? ''
            : formatForInput((value as int) / baseUnitsPerMajor);
    }
  }

  @override
  String describeSlot(SlotRef slot) {
    if (slot.line == null) return slot.field == 'farm' ? 'chaco' : 'área';
    final index = s.lines.indexWhere((l) => l.id == slot.line);
    return 'producto ${index + 1}: ${slot.field == 'dose' ? 'dosis' : 'producto'}';
  }

  @override
  void onDictationApplied(VoicePlanDraft shadow, String text) =>
      s._voiceApplied(shadow, text);
}
