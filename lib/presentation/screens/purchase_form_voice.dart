part of 'purchase_form_screen.dart';

/// «Completar por voz» en «Nueva compra» (F09, formulario único).
///
/// Motor de la compra, sin cambios: turno entero con Whisper small y haz de 5
/// (`purchaseSpeechPortFactoryProvider`) y la pista breve de la compra. El
/// intérprete es el de siempre (`interpretPurchase`) sobre un borrador de voz
/// **propio de cada dictado**; lo que dice se traduce a ranuras del
/// formulario y se incorpora con las reglas de `voice_form_merge.dart`.
///
/// Ranuras: cabecera `supplier`; por línea `product`, `quantity` (unidad
/// base), `price` (centavos por unidad), `currency` (sólo con precio), `fx`
/// (tipo de cambio escalado, sólo en USD) y, en compartido, `recipient`
/// (persona de «Toda para una persona»; `split` si se reparte).
class _PurchaseVoice implements VoiceFormTarget<VoicePurchaseDraft> {
  _PurchaseVoice(this.s);

  final _PurchaseFormScreenState s;
  VoiceCatalog? catalog;
  final List<String> _notices = [];
  int _seenDisagreements = 0;

  /// Línea de contexto de la sombra: el producto que la persona ya eligió en
  /// la última línea incompleta, para que «diez litros a 50…» se refiera a
  /// ella. No se propone de vuelta (lo eligió la persona).
  int? _contextKey;

  /// Catálogo del intérprete con lo que ya cargó el formulario (mismas
  /// consultas que la pantalla de voz anterior).
  void updateCatalog(_PurchaseCatalogs data) {
    final people = [
      for (final row in data.people)
        CatalogEntry(id: row['id']! as int, name: row['name']! as String),
    ];
    final holderId = s.ownerPersonId;
    final owner = s.personalOwnerId == null
        ? null
        : people.where((p) => p.id == s.personalOwnerId).firstOrNull;
    final active = data.campaigns
        .where((row) => row['status'] == 'ACTIVE')
        .firstOrNull;
    catalog = VoiceCatalog(
      products: [
        for (final row in data.products)
          CatalogEntry(
            id: row['id']! as int,
            name: row['name']! as String,
            unit: CatalogUnit.fromCode(row['unit'] as String?),
          ),
      ],
      suppliers: [
        for (final row in data.suppliers)
          CatalogEntry(id: row['id']! as int, name: row['name']! as String),
      ],
      people: owner == null ? people : [owner],
      activeCampaign: active == null
          ? null
          : CatalogEntry(
              id: active['id']! as int,
              name: active['name']! as String,
            ),
      loadedMode: s.loadedMode,
      personalOwner: owner,
      holderId: holderId,
      holderName: holderId == null
          ? null
          : people.where((p) => p.id == holderId).firstOrNull?.name ??
                'Titular',
    );
    s.voice?.session.setVocabularyHints(voicePurchaseTurnHints(catalog!));
  }

  bool get _shared => s.personalOwnerId == null;

  // --- Foto del formulario -------------------------------------------------

  @override
  FormSnapshot snapshot() => FormSnapshot(
    header: {'supplier': s.supplierId},
    lines: [
      for (final l in s.lines) LineSnapshot(l.id, l.voiceFields(_shared)),
    ],
  );

  @override
  int nextLineId() => s._nextLineId;

  // --- Interpretación ------------------------------------------------------

  @override
  VoicePurchaseDraft startShadow() {
    _notices.clear();
    _seenDisagreements = s.voice?.session.snapshot.numericDisagreements ?? 0;
    _contextKey = null;
    var shadow = VoicePurchaseDraft.start(catalog!);
    final last = s.lines.lastOrNull;
    final fields = last?.voiceFields(_shared);
    final product = catalog!.products
        .where((p) => p.id == last?.productId)
        .firstOrNull;
    if (fields != null &&
        product != null &&
        (fields['quantity'] == null || fields['price'] == null)) {
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
  VoicePurchaseDraft interpret(
    VoicePurchaseDraft shadow,
    String text,
    VoiceSessionSnapshot session,
  ) {
    final r = interpretPurchase(text, shadow, catalog!);
    if (r.otherIntent != null) _notices.add(_otherIntent(r.otherIntent!));
    if (r.ignoredRecipient != null) {
      // Modo individual (lámina I-15): un nombre dictado no crea ni asigna
      // persona; se dice qué completa este formulario, sin repetir lo dicho.
      _notices.add(
        'Parte del dictado no corresponde a este formulario y no se usó. '
        'Aquí se completan proveedor, fecha, producto, cantidad y precio.',
      );
    }
    if (r.unplacedPrice != null) _notices.add(r.unplacedPrice!.message);
    if (r.lineNotice != null) _notices.add(r.lineNotice!);
    var next = r.draft;
    // Desacuerdo numérico entre motores (sólo en la ruta por frases): los
    // números que cambió esta frase quedan por revisar, como antes.
    if (session.numericDisagreements > _seenDisagreements) {
      _seenDisagreements = session.numericDisagreements;
      next = _reviewDisagreement(
        shadow,
        next,
        session.reviewConflictFields,
        session.reviewSingleFields,
      );
    }
    return next;
  }

  static VoicePurchaseDraft _reviewDisagreement(
    VoicePurchaseDraft before,
    VoicePurchaseDraft after,
    Set<String> conflict,
    Set<String> single,
  ) {
    if (conflict.isEmpty && single.isEmpty) {
      return reviewPurchaseNumbers(before, after, numericDisagreementMessage);
    }
    final conflictFields = purchaseFieldsFor(conflict);
    final marked = reviewPurchaseNumbers(
      before,
      after,
      numericDisagreementMessage,
      only: conflictFields,
    );
    return reviewPurchaseNumbers(
      before,
      marked,
      singleSourceMessage,
      only: purchaseFieldsFor(single).difference(conflictFields),
    );
  }

  static String _otherIntent(VoiceIntent intent) => switch (intent) {
    VoiceIntent.unsupported =>
      'Los pagos y las consultas por voz no están disponibles. No se cambió '
          'la compra.',
    VoiceIntent.ambiguous =>
      'La frase mezcla varias operaciones. No se cambió la compra: dicte sólo '
          'la compra.',
    _ =>
      'Eso parece otra operación. No se cambió la compra: regístrela desde su '
          'propia pantalla.',
  };

  // --- Propuesta -----------------------------------------------------------

  @override
  VoiceProposal propose(VoicePurchaseDraft shadow, FormSnapshot now) {
    final header = <String, ProposedValue>{};
    final supplier = _entry(
      shadow.supplier,
      notInCatalog: (heard) =>
          '«$heard» no está entre los proveedores. Elija uno existente o '
          'créelo desde el selector; la voz no crea nada nuevo.',
    );
    if (supplier != null) header['supplier'] = supplier;

    ProposedValue? recipient;
    if (_shared && shadow.recipient.origin == FieldOrigin.voice) {
      recipient = _entry(
        shadow.recipient,
        notInCatalog: (heard) =>
            '«$heard» no está entre las personas. Elíjala en «¿Para quién '
            'es?».',
      );
    }
    final fx = shadow.exchangeRate.isResolved
        ? shadow.exchangeRate.value
        : null;

    final lines = <ProposedLine>[];
    for (final line in shadow.lines) {
      final fields = <String, ProposedValue>{};
      final context = line.key == _contextKey;
      final product = context
          ? null
          : _entry(
              line.product,
              notInCatalog: (heard) =>
                  '«$heard» no está en el catálogo. Elija uno existente o créelo '
                  'desde el selector; la voz no crea nada nuevo.',
            );
      if (product != null) fields['product'] = product;
      final unit = line.product.isResolved ? line.product.value?.unit : null;
      final quantity = _quantity(line, unit);
      if (quantity != null) fields['quantity'] = quantity;
      final price = _price(line, unit);
      if (price != null) fields['price'] = price;
      final currency = line.currency;
      // Con el precio por revisar, «bolivianos» no cambia nada (es la moneda
      // de toda línea nueva): proponerla dejaba un cambio de moneda que el
      // formulario no muestra y que «Deshacer» anunciaba como editado a mano
      // (2026-11-12). En dólares sí se propone: es un dato.
      final priceInReview = price == null || price.review != null;
      final defaultCurrency =
          currency.isResolved && currency.value == CurrencyCode.bob;
      if (currency.value != null &&
          line.price.value != null &&
          !(priceInReview && defaultCurrency)) {
        fields['currency'] = currency.isResolved
            ? ProposedValue(
                currency.value,
                display: _currencyName(currency.value!),
              )
            : ProposedValue(
                null,
                display: _currencyName(currency.value!),
                review: VoiceReview(
                  currency.message ?? 'Confirme la moneda.',
                  options: [
                    for (final c in CurrencyCode.values)
                      ReviewOption(_currencyName(c), c),
                  ],
                ),
              );
      }
      if (fx != null && currency.value == CurrencyCode.usd) {
        fields['fx'] = ProposedValue(
          fx,
          display: formatForInput(fx / fxScale, maxDecimals: 6),
        );
      }
      if (recipient != null) fields['recipient'] = recipient;
      if (fields.isNotEmpty) lines.add(ProposedLine(fields));
    }
    if (lines.isEmpty && recipient != null) {
      _notices.add(
        'Se oyó para quién es la compra, pero ningún producto: elija la '
        'persona en «¿Para quién es?» de cada línea.',
      );
    }
    if (lines.isEmpty && fx != null) {
      _notices.add(
        'Se oyó un tipo de cambio sin una línea en dólares: escríbalo en la '
        'línea que corresponda.',
      );
    }
    return VoiceProposal(header: header, lines: lines, notices: [..._notices]);
  }

  /// Un campo del catálogo (producto, proveedor, persona) dicho.
  static ProposedValue? _entry(
    DraftField<CatalogEntry> field, {
    required String Function(String heard) notInCatalog,
  }) {
    if (field.origin == FieldOrigin.preset) return null;
    switch (field.status) {
      case FieldStatus.resolved:
        final e = field.value!;
        if (field.review) {
          return ProposedValue(
            null,
            display: e.name,
            review: VoiceReview(
              field.message ?? 'Confirme «${e.name}».',
              options: [ReviewOption('Usar ${e.name}', e.id)],
            ),
          );
        }
        return ProposedValue(e.id, display: e.name);
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

  ProposedValue? _quantity(VoicePurchaseLine line, CatalogUnit? unit) {
    final f = line.quantity;
    final q = f.value;
    if (q == null) return null;
    final base = q.unit.toBase(q.thousandths);
    final display =
        '${formatForInput(q.thousandths / 1000)} ${q.unit.name == 'liter'
            ? 'L'
            : q.unit.name == 'milliliter'
            ? 'mL'
            : q.unit.name == 'kilogram'
            ? 'kg'
            : 'g'}';
    if (base == null || base <= 0) {
      return ProposedValue(
        null,
        display: display,
        review: const VoiceReview(
          'La cantidad dicha no es un número entero de mililitros o gramos: '
          'escríbala en el campo.',
        ),
      );
    }
    if (unit != null && q.unit.family != unit) {
      return ProposedValue(
        null,
        display: display,
        review: VoiceReview(
          'La unidad dicha ($display) no corresponde al producto, que se mide '
          'en ${unit == CatalogUnit.liter ? 'litros' : 'kilos'}: escriba la '
          'cantidad.',
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

  ProposedValue? _price(VoicePurchaseLine line, CatalogUnit? unit) {
    final f = line.price;
    final p = f.value;
    if (p == null) return null;
    final currency = line.currency.value;
    final amount = amountText(p.minorPerUnit, currency);
    final unitName = unit == null
        ? (p.perUnit == CatalogUnit.kilogram ? 'kg' : 'L')
        : (unit == CatalogUnit.kilogram ? 'kg' : 'L');
    if (p.perUnit != null && unit != null && p.perUnit != unit) {
      return ProposedValue(
        null,
        display: amount,
        review: const VoiceReview(
          'El precio se dijo por otra unidad que la del producto: escriba el '
          'precio por unidad.',
        ),
      );
    }
    if (f.isResolved && !f.review && !p.total) {
      return ProposedValue(p.minorPerUnit, display: '$amount por $unitName');
    }
    // Por revisar: precio por unidad o total de la línea, como antes.
    final q = line.quantity.value;
    final base = line.quantity.isResolved && q != null
        ? q.unit.toBase(q.thousandths)
        : null;
    final scaled = p.minorPerUnit * baseUnitsPerMajor;
    final total = base == null || base <= 0
        ? const ReviewOption(
            'Total de la línea',
            null,
            enabled: false,
            hint:
                'Para repartir el total hace falta la cantidad; o escriba el '
                'precio por unidad.',
          )
        : scaled % base != 0
        ? const ReviewOption(
            'Total de la línea',
            null,
            enabled: false,
            hint:
                'El total no se reparte en centavos exactos entre la '
                'cantidad: escriba el precio por unidad.',
          )
        : ReviewOption('Total de la línea', scaled ~/ base);
    return ProposedValue(
      null,
      display: amount,
      review: VoiceReview(
        p.total
            ? 'Se dijo un importe total: ${amountText(p.minorPerUnit, currency)}. '
                  'Elija «Total de la línea» para calcular el precio por '
                  'unidad, o escriba el precio por unidad.'
            : f.message ??
                  'No se dijo si $amount es el precio por $unitName o el total '
                      'de la línea.',
        options: [
          if (!p.total) ReviewOption('Por $unitName', p.minorPerUnit),
          total,
        ],
      ),
    );
  }

  static String _currencyName(CurrencyCode c) =>
      c == CurrencyCode.usd ? 'USD' : 'BOB';

  // --- Aplicación ----------------------------------------------------------

  @override
  void applyPlan(MergePlan plan) {
    s._voiceSetState(() {
      for (final c in plan.changes) {
        _set(c.slot, c.after);
      }
      for (final n in plan.newLines) {
        final line = _PurchaseLineEditor(n.line);
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
      // El formulario siempre tiene al menos una línea.
      if (s.lines.isEmpty) s.lines.add(s._newLine());
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
      if (slot.field == 'supplier') s.supplierId = value as int?;
      return;
    }
    final line = s.lines.where((l) => l.id == slot.line).firstOrNull;
    if (line != null) _setLine(line, slot.field, value);
  }

  void _setLine(_PurchaseLineEditor line, String field, Object? value) {
    switch (field) {
      case 'product':
        line.productId = value as int?;
      case 'quantity':
        line.quantity.text = value == null
            ? ''
            : formatForInput((value as int) / baseUnitsPerMajor);
        line.quantityError = null;
      case 'price':
        line.price.text = value == null
            ? ''
            : formatForInput((value as int) / 100, maxDecimals: 2);
        line.priceError = null;
      case 'currency':
        line.currency = (value as CurrencyCode?) ?? CurrencyCode.bob;
      case 'fx':
        line.fx.text = value == null
            ? ''
            : formatForInput((value as int) / fxScale, maxDecimals: 6);
        line.fxError = null;
      case 'recipient':
        if (value is int) {
          line.allocationMode = _AllocationMode.single;
          line.singlePersonId = value;
        } else if (value == null) {
          line.allocationMode = null;
          line.singlePersonId = null;
        }
    }
  }

  @override
  String describeSlot(SlotRef slot) {
    if (slot.line == null) return 'proveedor';
    final index = s.lines.indexWhere((l) => l.id == slot.line);
    final name = switch (slot.field) {
      'product' => 'producto',
      'quantity' => 'cantidad',
      'price' => 'precio',
      'currency' => 'moneda',
      'fx' => 'tipo de cambio',
      'recipient' => 'destinatario',
      _ => slot.field,
    };
    return 'línea ${index + 1}: $name';
  }

  @override
  void onDictationApplied(VoicePurchaseDraft shadow, String text) =>
      s._voiceApplied(shadow, text);
}

extension on _PurchaseLineEditor {
  /// Valores canónicos de la línea para el dictado (`null` = vacío).
  Map<String, Object?> voiceFields(bool shared) {
    Object? canon(String text, int? Function(String) parse) {
      final t = text.trim();
      if (t.isEmpty) return null;
      return parse(t) ?? 'texto:$t';
    }

    final price = canon(this.price.text, tryParseMinor);
    return {
      'product': productId,
      'quantity': canon(quantity.text, tryParseBase),
      'price': price,
      // La moneda viene puesta (BOB) en toda línea nueva: sólo cuenta como
      // dato cuando hay precio o cuando es otra (dólares elegidos a mano o
      // dictados con el precio por revisar). Así lo que puso la voz coincide
      // con lo que se ve y «Deshacer» puede devolverla (2026-11-12).
      'currency': price == null && currency == CurrencyCode.bob
          ? null
          : currency,
      'fx': currency == CurrencyCode.usd
          ? canon(fx.text, (t) {
              final v = tryParseDecimal(t);
              return v == null ? null : (v * fxScale).round();
            })
          : null,
      if (shared)
        'recipient': switch (allocationMode) {
          null => null,
          _AllocationMode.single => singlePersonId,
          _AllocationMode.split => 'split',
        },
    };
  }
}
