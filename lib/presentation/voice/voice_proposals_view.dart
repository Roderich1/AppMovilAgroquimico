/// Vista de diagnóstico: lo que propuso cada motor (F09, POCO 2026-11-09).
///
/// Sólo existe en la compilación de diagnóstico ([voiceDiagnosticsBuild]) y
/// sólo se abre con un toque explícito. Muestra, por frase:
///
/// * el texto de Vosk y el de la revisión (Whisper base), o por qué no hubo
///   revisión;
/// * qué texto se eligió y con qué regla;
/// * qué tipo de diferencia de cifras hubo;
/// * cómo interpreta el borrador **cada propuesta por separado**, sobre un
///   borrador vacío, sin tocar el borrador real.
///
/// El contenido vive sólo en memoria ([VoiceProposalsInspector]). Cerrar la
/// vista lo borra; también lo borran descartar o registrar el borrador y
/// salir de la pantalla. La vista no escribe registros, archivos ni
/// evidencia, no cambia el consentimiento y no escribe nada del negocio.
library;

import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../domain/numeric_input.dart';
import '../../voice/port/review_discrepancy.dart';
import '../../voice/port/review_selection.dart';
import '../../voice/port/voice_engine_diagnostics.dart';
import '../../voice_draft/catalog/voice_catalog.dart';
import '../../voice_draft/core/draft_field.dart';
import '../../voice_draft/purchase/purchase_interpreter.dart';
import '../../voice_draft/purchase/voice_purchase_draft.dart';
import '../../voice_draft/text/units.dart';

/// Botón que abre la vista. No se dibuja fuera de la compilación de
/// diagnóstico.
class VoiceProposalsButton extends StatelessWidget {
  const VoiceProposalsButton({
    super.key,
    required this.describe,
    this.inspector,
    this.enabled = voiceDiagnosticsBuild,
  });

  /// Interpretación de un texto sobre un borrador vacío, en líneas legibles.
  final List<String> Function(String text) describe;

  /// Para pruebas; por defecto, el de la app.
  final VoiceProposalsInspector? inspector;

  /// Para pruebas; por defecto, sólo en la compilación de diagnóstico.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final store = inspector ?? VoiceProposalsInspector.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: OutlinedButton.icon(
          key: const Key('voz-diagnostico-propuestas'),
          onPressed: store.items.isEmpty ? null : () => _open(context, store),
          icon: const Icon(Icons.compare_arrows),
          label: Text(
            'Diagnóstico: ver lo que propuso cada motor '
            '(${store.items.length})',
          ),
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    VoiceProposalsInspector store,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _ProposalsDialog(proposals: store.items, describe: describe),
    );
    // Cerrar la vista borra lo que mostró.
    store.clear();
  }
}

class _ProposalsDialog extends StatelessWidget {
  const _ProposalsDialog({required this.proposals, required this.describe});

  final List<EngineProposal> proposals;
  final List<String> Function(String text) describe;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('voz-diagnostico-vista'),
      title: const Text('Lo que propuso cada motor'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            const Text(
              'Sólo para revisar ahora. Nada de esto se guarda: al cerrar se '
              'borra. El borrador no cambia.',
            ),
            for (final p in proposals) _ProposalCard(p, describe),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('voz-diagnostico-cerrar'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar y borrar'),
        ),
      ],
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard(this.p, this.describe);

  final EngineProposal p;
  final List<String> Function(String text) describe;

  @override
  Widget build(BuildContext context) {
    final bold = Theme.of(context).textTheme.titleSmall;
    final review = p.review;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Frase ${(p.seq ?? 0) + 1}', style: bold),
            const SizedBox(height: 6),
            Text('Vosk: «${p.vosk}»'),
            Text(
              review == null || review.isEmpty
                  ? 'Whisper: sin texto (${reviewOutcomeText(p.reviewOutcome)})'
                  : 'Whisper: «$review»',
            ),
            const SizedBox(height: 6),
            Text('Se usó: ${chosenText(p)}'),
            Text('Regla: ${verdictText(p.verdict, late: p.late)}'),
            Text(
              'Diferencias de cifras: ${discrepanciesText(p.discrepancies)}',
            ),
            const SizedBox(height: 6),
            Text('Interpretación de Vosk', style: bold),
            for (final l in describe(p.vosk)) Text('· $l'),
            if (review != null && review.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Interpretación de Whisper', style: bold),
              for (final l in describe(review)) Text('· $l'),
            ],
          ],
        ),
      ),
    );
  }
}

/// Qué texto llegó al formulario.
String chosenText(EngineProposal p) {
  if (p.late) return 'Vosk (Whisper llegó tarde y se descartó)';
  return p.revised ? 'Whisper' : 'Vosk';
}

/// Regla que eligió el texto, en palabras.
String verdictText(ReviewVerdict v, {bool late = false}) {
  if (late) return 'Whisper no llegó dentro del límite de 5 s.';
  return switch (v) {
    ReviewVerdict.accepted =>
      'Las cifras, unidades y monedas coinciden: se usa Whisper.',
    ReviewVerdict.notRun => 'No hubo segunda pasada para esta frase.',
    ReviewVerdict.empty => 'Whisper no devolvió texto.',
    ReviewVerdict.nonSpeech => 'Whisper devolvió texto típico de ruido.',
    ReviewVerdict.degenerate =>
      'Whisper repitió palabras o cambió mucho la longitud.',
    ReviewVerdict.quantities =>
      'Las listas de cifras, unidades y monedas no son iguales: se usa Vosk '
          'y las cifras quedan «Revisar». Un dato que sólo uno oyó también '
          'cuenta como distinto.',
    ReviewVerdict.format =>
      'Mismos valores escritos de otra forma: se usa Vosk, sin desacuerdo.',
    ReviewVerdict.unchecked => 'No había con qué comparar cifras: se usa Vosk.',
    ReviewVerdict.timedOut => 'Whisper no llegó dentro del límite de 5 s.',
  };
}

/// Resultado de la segunda pasada, en palabras.
String reviewOutcomeText(String code) => switch (code) {
  'ok' => 'terminó',
  'aborted' => 'se cortó al agotar el límite',
  'budget-exhausted' => 'no empezó: el límite ya se había agotado',
  'queue-full' => 'no se pidió: había otras frases esperando',
  'off' => 'revisión desactivada',
  'unavailable' => 'modelo no disponible',
  'cancelled' => 'cancelada',
  'error' => 'falló',
  _ => 'sin dato',
};

/// Diferencias de cifras, en palabras.
String discrepanciesText(List<FactDiscrepancy> list) {
  if (list.isEmpty) return 'ninguna';
  return list.map(discrepancyText).join('; ');
}

String discrepancyText(FactDiscrepancy d) {
  final field = switch (d.field) {
    ReviewField.quantity => 'cantidad',
    ReviewField.price => 'precio',
    ReviewField.area => 'área',
    ReviewField.number => 'cifra',
    ReviewField.unit => 'unidad',
    ReviewField.currency => 'moneda',
  };
  final who = d.onlyIn == ReviewSide.first ? 'Vosk' : 'Whisper';
  return switch (d.kind) {
    DiscrepancyKind.differentValue => '$field: valor distinto',
    DiscrepancyKind.missing => '$field: sólo la oyó $who',
    DiscrepancyKind.differentUnit => '$field: unidad distinta',
    DiscrepancyKind.differentCurrency => '$field: moneda distinta',
    DiscrepancyKind.equivalentFormat => '$field: mismo valor, otra forma',
    DiscrepancyKind.extractionFailed => '$field: una cifra no se pudo leer',
    DiscrepancyKind.ambiguousAlignment =>
      '$field: no se puede saber qué dato corresponde a cuál',
  };
}

/// Cómo interpreta la compra un texto, sobre un borrador vacío.
List<String> describePurchaseProposal(String text, VoiceCatalog catalog) {
  final r = interpretPurchase(text, VoicePurchaseDraft.start(catalog), catalog);
  final d = r.draft;
  final out = <String>[];
  if (r.otherIntent != null) out.add('Parece otra operación, no una compra.');
  if (d.supplier.status != FieldStatus.missing || d.supplier.heard != null) {
    out.add('Proveedor: ${_entry(d.supplier)}');
  }
  if (d.recipient.status != FieldStatus.missing || d.recipient.heard != null) {
    out.add('Recibe: ${_entry(d.recipient)}');
  }
  for (var i = 0; i < d.lines.length; i++) {
    final l = d.lines[i];
    out.add(
      'Línea ${i + 1}: ${_entry(l.product)}; ${_quantity(l.quantity)}; '
      '${_price(l.price)}; moneda ${_currency(l.currency)}',
    );
  }
  if (r.lineNotice != null) out.add(r.lineNotice!);
  if (out.isEmpty) out.add('No completa nada del borrador.');
  return out;
}

String _state(DraftField<Object?> f, String Function() value) =>
    switch (f.status) {
      FieldStatus.resolved => value(),
      FieldStatus.ambiguous =>
        '${f.value == null ? '' : '${value()} '}(ambiguo'
            '${f.heard == null ? '' : ', oído «${f.heard}»'})',
      FieldStatus.invalid =>
        'no válido${f.heard == null ? '' : ' («${f.heard}»)'}',
      FieldStatus.missing =>
        f.heard == null ? 'falta' : 'fuera del catálogo («${f.heard}»)',
    };

String _entry(DraftField<CatalogEntry> f) =>
    _state(f, () => f.value?.name ?? '');

String _quantity(DraftField<SpokenQuantity> f) =>
    'cantidad ${_state(f, () {
      final q = f.value;
      if (q == null) return '';
      return '${formatForInput(q.thousandths / 1000)} ${_unit(q.unit)}';
    })}';

String _price(DraftField<SpokenPrice> f) =>
    'precio ${_state(f, () {
      final p = f.value;
      if (p == null) return '';
      final amount = formatForInput(p.minorPerUnit / 100, maxDecimals: 2);
      if (p.total) return '$amount en total';
      final per = p.perUnit;
      return per == null ? '$amount (sin unidad)' : '$amount por ${_unit(per)}';
    })}';

String _currency(DraftField<CurrencyCode> f) =>
    _state(f, () => f.value?.name.toUpperCase() ?? '');

String _unit(Object unit) => switch (unit) {
  SpokenUnit.liter => 'L',
  SpokenUnit.milliliter => 'mL',
  SpokenUnit.kilogram => 'kg',
  SpokenUnit.gram => 'g',
  CatalogUnit.liter => 'L',
  CatalogUnit.kilogram => 'kg',
  _ => '$unit',
};
