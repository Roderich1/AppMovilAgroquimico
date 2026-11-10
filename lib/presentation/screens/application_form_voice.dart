part of 'application_form_screen.dart';

/// «Completar por voz» en «Nueva aplicación» (F09, formulario único).
///
/// Motor de siempre de la aplicación: Vosk por frases con revisión de Whisper
/// base (`speechPortFactoryProvider`) y la pista del catálogo. Intérprete:
/// `interpretApplication` sobre un borrador de voz propio de cada dictado.
///
/// Ranuras: cabecera `farm` (id), `area` (m²) y `plan` (sólo para elegir un
/// plan pendiente, que abre el recorrido habitual «Aplicar este plan»); por
/// línea `product` (id) y `quantity` (cantidad usada, unidad base).
///
/// Reglas de la aplicación que la voz no esquiva:
/// - el responsable es el dueño del chaco; un chaco de otra persona, con una
///   persona ya elegida, no se aplica solo: cambiarlo vacía la mezcla, así
///   que se pregunta;
/// - una línea usa las existencias del responsable; sin existencias,
///   «Continuar» y «Confirmar» la rechazan con su aviso de siempre;
/// - nada toca inventario ni cuentas hasta «Confirmar aplicación».
class _ApplicationVoice implements VoiceFormTarget<VoiceApplicationDraft> {
  _ApplicationVoice(this.s);

  final _ApplicationFormScreenState s;
  VoiceCatalog? catalog;
  final List<String> _notices = [];
  int _seenDisagreements = 0;

  /// Catálogo del intérprete (personas que aplican, chacos con su dueño,
  /// productos y planes pendientes), con las mismas lecturas de siempre.
  Future<void> loadCatalog() async {
    final next = await s.ref
        .read(voiceDraftGatewayProvider)
        .applicationCatalog();
    catalog = next;
    s.voice?.session.setVocabularyHints(voiceVocabularyHints(next));
  }

  @override
  FormSnapshot snapshot() => FormSnapshot(
    header: {'farm': s.farmId, 'area': _areaCanon(s.area.text), 'plan': null},
    lines: [
      for (final l in s.lines)
        LineSnapshot(l.id, {
          'product': l.product['product_id'],
          'quantity': l.quantityBase > 0 ? l.quantityBase : null,
        }),
    ],
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
  VoiceApplicationDraft? startShadow() {
    final c = catalog;
    if (c == null) return null;
    _notices.clear();
    _seenDisagreements = s.voice?.session.snapshot.numericDisagreements ?? 0;
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
    final farmField = shadow.farm;
    var farmFromVoice = false;
    if (s.widget.planId == null) {
      final farm = _entry(
        farmField,
        notInCatalog: (heard) =>
            '«$heard» no está entre los chacos de quienes aplican. Elija uno '
            'existente o créelo desde el selector; la voz no crea nada nuevo.',
      );
      if (farm != null) {
        farmFromVoice = farm.value != null;
        final owner = farm.value == null ? null : c.farmOwners[farm.value];
        final personSet = s.personId != null && !s.personalMode;
        if (owner != null && personSet && owner.id != s.personId) {
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
      // El área que trae un chaco dictado se registra para poder deshacerla;
      // la dictada, siempre.
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
    s._voiceSetState(() {
      for (final c in plan.changes) {
        _set(c.slot, c.after);
      }
      for (final n in plan.newLines) {
        final line = _ApplicationLineEditor(
          s._productRow(n.values['product'] as int?),
          quantityBase: 0,
          id: n.line,
        );
        if (n.line >= s._nextLineId) s._nextLineId = n.line + 1;
        s.lines.add(line);
        n.values.forEach((field, value) => _setLine(line, field, value));
      }
      if (!plan.changesNothing) s.dirty = true;
    });
    s._refreshVoiceLines();
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
    if (slot.line == null && slot.field == 'plan') {
      if (value is int) s._openPlanFromVoice(value);
      return;
    }
    s._voiceSetState(() {
      _set(slot, value);
      s.dirty = true;
    });
    s._refreshVoiceLines();
  }

  void _set(SlotRef slot, Object? value) {
    if (slot.line == null) {
      switch (slot.field) {
        case 'farm':
          s._selectFarmForVoice(value as int?);
        case 'area':
          s.area.text = value == null ? '' : _areaInput(value as int);
          s.areaError = null;
      }
      return;
    }
    final line = s.lines.where((l) => l.id == slot.line).firstOrNull;
    if (line != null) _setLine(line, slot.field, value);
  }

  void _setLine(_ApplicationLineEditor line, String field, Object? value) {
    switch (field) {
      case 'product':
        line.product = s._productRow(value as int?);
      case 'quantity':
        line.quantityBase = (value as int?) ?? 0;
    }
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
    final index = s.lines.indexWhere((l) => l.id == slot.line);
    return 'producto ${index + 1}: '
        '${slot.field == 'quantity' ? 'cantidad' : 'producto'}';
  }

  @override
  void onDictationApplied(VoiceApplicationDraft shadow, String text) =>
      s._voiceApplied(shadow, text);
}
