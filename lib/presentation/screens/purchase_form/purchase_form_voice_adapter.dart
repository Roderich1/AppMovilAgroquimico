import 'package:flutter/foundation.dart' show VoidCallback;

import '../../../domain/models.dart' show CurrencyCode;
import '../../../domain/money.dart';
import '../../widgets/common.dart' show formatForInput;
import '../../../voice/session/voice_session_state.dart';
import '../../../voice_draft/catalog/voice_catalog.dart';
import '../../../voice_draft/core/draft_field.dart';
import '../../../voice_draft/core/numeric_review.dart';
import '../../../voice_draft/interpretation/voice_intent.dart';
import '../../../voice_draft/purchase/purchase_interpreter.dart';
import '../../../voice_draft/purchase/voice_purchase_draft.dart';
import '../../../voice_draft/text/units.dart' show CatalogUnit, SpokenUnit;
import '../../../voice_evidence/draft_snapshot.dart'
    show formCatalogEntry, formDraftField;
import '../../voice/voice_draft_widgets.dart' show voicePurchaseTurnHints;
import '../../voice/voice_form_dictation.dart';
import 'purchase_form_notifier.dart';
import 'purchase_form_state.dart';

/// «Completar por voz» en «Nueva compra» (F09, formulario único).
class PurchaseFormVoiceAdapter implements VoiceFormTarget<VoicePurchaseDraft> {
  PurchaseFormVoiceAdapter({
    required this.readState,
    required this.readNotifier,
    required this.readVoice,
    required this.onApplied,
    required this.onAfterStateSync,
  });

  final PurchaseFormState Function() readState;
  final PurchaseFormNotifier Function() readNotifier;
  final VoiceFormDictation<VoicePurchaseDraft>? Function() readVoice;
  final void Function(
    VoicePurchaseDraft shadow,
    String text,
    Map<int, int> lineIds,
  )
  onApplied;
  final VoidCallback onAfterStateSync;

  VoiceCatalog? catalog;
  List<CatalogEntry> _campaigns = const [];
  final List<String> _notices = [];
  int _seenDisagreements = 0;
  int? _contextKey;

  void updateCatalog(
    PurchaseCatalogs data, {
    required PurchaseFormState state,
  }) {
    final people = [
      for (final row in data.people)
        CatalogEntry(id: row['id']! as int, name: row['name']! as String),
    ];
    final holderId = state.ownerPersonId;
    final owner = state.personalOwnerId == null
        ? null
        : people.where((p) => p.id == state.personalOwnerId).firstOrNull;
    final active = data.campaigns
        .where((row) => row['status'] == 'ACTIVE')
        .firstOrNull;
    _campaigns = [
      for (final row in data.campaigns)
        CatalogEntry(id: row['id']! as int, name: row['name']! as String),
    ];
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
      loadedMode: state.loadedMode,
      personalOwner: owner,
      holderId: holderId,
      holderName: holderId == null
          ? null
          : people.where((p) => p.id == holderId).firstOrNull?.name ??
                'Titular',
    );
    readVoice()?.session.setVocabularyHints(voicePurchaseTurnHints(catalog!));
  }

  bool get _shared => readState().personalOwnerId == null;

  VoicePurchaseDraft evidenceDraft() {
    final c = catalog!;
    final state = readState();
    final people = {
      for (final l in state.lines)
        if (l.productId != null)
          _shared
              ? (l.allocationMode == AllocationMode.single
                    ? l.singlePersonId
                    : null)
              : state.personalOwnerId,
    };
    final fx = state.lines
        .where((l) => l.currency == CurrencyCode.usd)
        .map((l) => l.exchangeRateScaled)
        .where((v) => v != null && v > 0)
        .firstOrNull;
    return VoicePurchaseDraft(
      supplier: formDraftField(formCatalogEntry(c.suppliers, state.supplierId)),
      campaign: formDraftField(formCatalogEntry(_campaigns, state.campaignId)),
      recipient: formDraftField(
        people.length == 1 ? formCatalogEntry(c.people, people.single) : null,
      ),
      exchangeRate: formDraftField(fx),
      lines: [for (final l in state.lines) _evidenceLine(l, c)],
      nextLineKey: state.nextLineId,
    );
  }

  static VoicePurchaseLine _evidenceLine(PurchaseLineData l, VoiceCatalog c) {
    final product = formCatalogEntry(c.products, l.productId);
    final unit = product?.unit;
    return VoicePurchaseLine(
      key: l.id,
      product: formDraftField(product),
      quantity: formDraftField(
        l.quantityBase > 0
            ? SpokenQuantity(
                l.quantityBase,
                unit == CatalogUnit.kilogram
                    ? SpokenUnit.kilogram
                    : SpokenUnit.liter,
              )
            : null,
      ),
      price: formDraftField(
        l.priceMinor > 0 ? SpokenPrice(l.priceMinor, perUnit: unit) : null,
      ),
      currency: formDraftField(l.currency),
    );
  }

  @override
  FormSnapshot snapshot() {
    final state = readState();
    return FormSnapshot(
      header: {'supplier': state.supplierId},
      lines: [
        for (final l in state.lines) LineSnapshot(l.id, l.voiceFields(_shared)),
      ],
    );
  }

  @override
  int nextLineId() => readState().nextLineId;

  @override
  VoicePurchaseDraft startShadow() {
    _notices.clear();
    _seenDisagreements =
        readVoice()?.session.snapshot.numericDisagreements ?? 0;
    _contextKey = null;
    var shadow = VoicePurchaseDraft.start(catalog!);
    final last = readState().lines.lastOrNull;
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
      _notices.add(
        'Parte del dictado no corresponde a este formulario y no se usó. '
        'Aquí se completan proveedor, fecha, producto, cantidad y precio.',
      );
    }
    if (r.unplacedPrice != null) _notices.add(r.unplacedPrice!.message);
    if (r.lineNotice != null) _notices.add(r.lineNotice!);
    var next = r.draft;
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
      final proposedLine = _proposeLine(line, recipient: recipient, fx: fx);
      if (proposedLine != null) lines.add(proposedLine);
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

  ProposedLine? _proposeLine(
    VoicePurchaseLine line, {
    required ProposedValue? recipient,
    required int? fx,
  }) {
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
    if (fields.isEmpty) return null;
    return ProposedLine(fields, source: line.key);
  }

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

  @override
  void applyPlan(MergePlan plan) {
    readNotifier().applyVoicePlan(plan);
    onAfterStateSync();
  }

  @override
  void applyUndo(UndoPlan plan) {
    readNotifier().applyVoiceUndo(plan);
    onAfterStateSync();
  }

  @override
  void setSlot(SlotRef slot, Object? value) {
    readNotifier().setVoiceSlot(slot, value);
    onAfterStateSync();
  }

  @override
  String describeSlot(SlotRef slot) {
    if (slot.line == null) return 'proveedor';
    final index = readState().lines.indexWhere((l) => l.id == slot.line);
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
  void onDictationApplied(
    VoicePurchaseDraft shadow,
    String text,
    Map<int, int> lineIds,
  ) => onApplied(shadow, text, lineIds);
}
