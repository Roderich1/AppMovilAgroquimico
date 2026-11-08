/// Piezas comunes de las pantallas de borrador por voz (#16): el mismo
/// aviso, el mismo estado por campo, la misma elección contra el catálogo, los
/// mismos bloqueos y el mismo tratamiento de lo dictado en compra,
/// planificación y aplicación.
library;

import 'package:flutter/material.dart';

import '../../voice_draft/catalog/voice_catalog.dart';
import '../../voice_draft/core/voice_draft_controller.dart';
import '../widgets/adaptive_entity_picker.dart';
import '../../voice_draft/core/draft_field.dart';
import '../../voice_draft/interpretation/voice_intent.dart';

/// Lleva la cuenta del texto cerrado ya interpretado de una sesión de voz y
/// entrega **sólo lo nuevo**. Lo provisional nunca pasa por aquí: sólo el
/// texto que la sesión ya cerró (`committedText`).
/// Nombres que pueden dictarse en este borrador, como pista de vocabulario
/// para el reconocimiento local: productos, personas, proveedores, chacos y
/// la campaña activa. Sólo nombres; sin cantidades ni importes.
List<String> voiceVocabularyHints(VoiceCatalog catalog) {
  final seen = <String>{};
  return [
    for (final entry in [
      ...catalog.products,
      ...catalog.people,
      ...catalog.suppliers,
      ...catalog.farms,
      if (catalog.activeCampaign != null) catalog.activeCampaign!,
    ])
      if (seen.add(entry.name.trim().toLowerCase())) entry.name.trim(),
  ];
}

class VoiceSegmentFeed {
  String _consumed = '';

  /// Texto cerrado nuevo desde la última vez, o `null`. Si [ready] es falso
  /// (el borrador aún carga), no consume nada y lo entregará después.
  String? take(String committed, {required bool ready}) {
    if (!committed.startsWith(_consumed)) {
      // La sesión se descartó o se reinició: se sigue desde su texto actual.
      _consumed = committed;
      return null;
    }
    if (!ready || committed.length <= _consumed.length) return null;
    final fresh = committed.substring(_consumed.length).trim();
    _consumed = committed;
    return fresh.isEmpty ? null : fresh;
  }
}

/// Salida de una pantalla de borrador (#120, F09-D2).
///
/// El defecto: tras registrar bien, aparecía «¿Descartar el borrador? No se
/// registró…». La pantalla marcaba que salía con `setState` y llamaba a
/// `maybePop` **en el mismo fotograma**; el `PopScope` aún tenía el
/// `canPop: false` del borrador con trabajo, así que `maybePop` lo trataba
/// como un «Atrás» y abría el diálogo de descarte. Lo mismo pasaba al
/// cancelar.
///
/// Ahora:
/// - un borrador confirmado o descartado nunca pregunta al salir;
/// - la salida se hace **después** del fotograma que publica `canPop: true`,
///   y sólo una vez (un doble toque no saca dos pantallas);
/// - un fallo al escribir no sale: el borrador sigue editable con su error.
mixin VoiceDraftExit<W extends StatefulWidget> on State<W> {
  bool _leaving = false;

  /// Ya se decidió salir: el siguiente «Atrás» no vuelve a preguntar.
  bool get leaving => _leaving;

  /// `PopScope.canPop`: sin preguntar si ya se sale, si el borrador está
  /// cerrado (confirmado o descartado) o si no hay nada que perder; nunca
  /// durante la escritura.
  bool canPopDraft(DraftPhase? phase, {required bool hasWork}) =>
      _leaving ||
      phase == DraftPhase.confirmed ||
      phase == DraftPhase.discarded ||
      (phase != DraftPhase.confirming && !hasWork);

  /// Si un «Atrás» bloqueado debe preguntar antes de descartar: sólo con un
  /// borrador que todavía se edita.
  bool shouldAskBeforeDiscard(DraftPhase? phase) =>
      !_leaving && (phase == null || phase == DraftPhase.editing);

  /// Sale de la pantalla con [result], una sola vez y con el `PopScope` ya
  /// reconstruido.
  void leave([Object? result]) {
    if (_leaving || !mounted) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop(result);
    });
  }

  /// Marca la salida sin navegar: quien llama sustituye la pantalla (el
  /// formulario manual con `pushReplacement`).
  void markLeaving() {
    if (mounted) setState(() => _leaving = true);
  }
}

/// Aviso común: la voz sólo prepara un borrador.
class VoiceDraftNotice extends StatelessWidget {
  const VoiceDraftNotice({
    super.key,
    required this.confirmLabel,
    required this.catalogs,
    this.createInPicker = false,
  });

  /// Texto del botón que registra («Registrar compra»).
  final String confirmLabel;

  /// Qué se busca en los catálogos («Los productos, proveedores y personas»).
  final String catalogs;

  /// Si los selectores de esta pantalla ofrecen «Crear …».
  final bool createInPicker;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        'La voz sólo prepara un borrador. Nada se registra hasta que usted '
        'revise y pulse «$confirmLabel». Lo que corrija a mano no lo cambia '
        'la voz. $catalogs se buscan en sus catálogos; la voz no crea nada '
        'nuevo. ${createInPicker ? 'Si falta uno, puede darlo de alta desde su selector sin perder el borrador.' : 'Si falta uno, créelo antes en Catálogos.'}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );
}

/// Un tramo de dictado cerrado que ya se interpretó, y si cambió algo.
final class VoiceHeardSegment {
  const VoiceHeardSegment(
    this.text, {
    required this.changedDraft,
    this.keptManual = 0,
  });

  /// Lo oído, tal cual. Sólo en memoria, nunca en registros.
  final String text;

  /// Si la interpretación cambió algún campo o añadió una línea.
  final bool changedDraft;

  /// Campos que el tramo quería cambiar y se conservaron por ser manuales.
  final int keptManual;

  /// A partir del resultado de interpretar el tramo.
  factory VoiceHeardSegment.from(String text, VoicePatchOutcome outcome) =>
      VoiceHeardSegment(
        text,
        changedDraft: outcome.applied > 0,
        keptManual: outcome.keptManual,
      );
}

/// Lo dictado ya interpretado (lo «refinado»), con lo que hizo cada tramo.
///
/// POCO §2.3 (2026-11-05): bajo «Ya aplicado al borrador» aparecían frases
/// que no habían cambiado nada, y el rótulo hacía creer que sí. Ahora cada
/// tramo dice si cambió el borrador o no, y por qué no cuando se sabe.
class VoiceAppliedPanel extends StatelessWidget {
  const VoiceAppliedPanel({super.key, required this.segments});
  final List<VoiceHeardSegment> segments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('voz-aplicado'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lo último que se oyó', style: theme.textTheme.labelMedium),
          for (final (i, s) in segments.reversed.take(3).indexed) ...[
            const SizedBox(height: 4),
            Text(
              s.changedDraft
                  ? 'Aplicado al borrador:'
                  : s.keptManual > 0
                  ? 'No cambió el borrador: se conserva lo corregido a mano.'
                  : 'No cambió el borrador: no se reconoció nada que '
                        'completar.',
              key: Key('voz-oido-estado-$i'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: s.changedDraft
                    ? theme.colorScheme.primary
                    : theme.colorScheme.tertiary,
              ),
            ),
            Text('«${s.text}»'),
          ],
        ],
      ),
    );
  }
}

/// El dictado parece otra operación: no se aplicó nada.
class VoiceOtherIntentBanner extends StatelessWidget {
  const VoiceOtherIntentBanner({
    super.key,
    required this.intent,
    required this.current,
  });
  final VoiceIntent intent;

  /// La operación de esta pantalla, en palabras («compra»).
  final String current;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('voz-otra-intencion'),
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(switch (intent) {
        VoiceIntent.purchase || VoiceIntent.application || VoiceIntent.plan =>
          'Eso parece otra operación. No se cambió este borrador de $current: '
              'regístrela desde su propia pantalla.',
        VoiceIntent.unsupported =>
          'Los pagos y las consultas por voz no están disponibles. No se cambió '
              'el borrador.',
        _ =>
          'La frase mezcla varias operaciones. No se cambió el borrador: dicte '
              'sólo la $current.',
      }),
    ),
  );
}

/// Lo que impide confirmar.
class VoiceBlockersPanel extends StatelessWidget {
  const VoiceBlockersPanel({super.key, required this.blockers});
  final List<String> blockers;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('voz-bloqueos'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Para registrar falta:'),
        for (final b in blockers) Text('• $b'),
      ],
    ),
  );
}

/// Etiqueta, estado del campo y el control para corregirlo.
class DraftFieldRow extends StatelessWidget {
  const DraftFieldRow({
    super.key,
    required this.label,
    required this.field,
    required this.child,
    this.labelInChild = false,
  });

  final String label;
  final DraftField<Object?> field;
  final Widget child;

  /// El control ya muestra la etiqueta (un selector): aquí sólo el estado.
  final bool labelInChild;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (text, color) = switch (field.status) {
      FieldStatus.resolved => (
        switch (field.origin) {
          FieldOrigin.manual => 'Corregido a mano',
          FieldOrigin.preset => 'Propuesto',
          _ => 'Dictado',
        },
        scheme.primary,
      ),
      FieldStatus.ambiguous => ('Ambiguo: elija', scheme.tertiary),
      FieldStatus.missing => ('Falta', scheme.error),
      FieldStatus.invalid => ('No válido', scheme.error),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: labelInChild ? const SizedBox.shrink() : Text(label),
              ),
              Text(
                text,
                semanticsLabel: '$label: $text',
                style: TextStyle(color: color),
              ),
            ],
          ),
          if (field.heard != null && !field.isResolved)
            Text(
              'Oído: «${field.heard}»',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (field.message != null && !field.isResolved)
            Text(field.message!, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// El selector de los formularios (`AdaptiveEntityPicker`, UX del jurado)
/// sobre las entradas del catálogo: búsqueda, hoja con las opciones y, si la
/// pantalla lo ofrece, «Crear …» para que **la persona** dé de alta lo que
/// falta sin perder el borrador. Lo creado vuelve elegido ([onCreate]).
///
/// Diferencias deliberadas con el formulario:
/// - nunca elige solo la única opción (`autoSelectSingle: false`): una
///   elección automática contaría como corrección manual y la voz ya no
///   podría cambiarla (ADR-003: no autoelegir entidades críticas);
/// - no se limpia (`allowClear: false`): un campo vaciado a mano quedaría
///   sin marca de manual;
/// - las opciones parecidas a lo dictado van primero y lo dicen.
class VoiceEntityPicker extends StatelessWidget {
  const VoiceEntityPicker({
    super.key,
    required this.label,
    required this.entries,
    required this.field,
    required this.enabled,
    required this.onPick,
    this.createLabel,
    this.onCreate,
    this.showUnit = false,
  });

  final String label;
  final List<CatalogEntry> entries;
  final DraftField<CatalogEntry> field;
  final bool enabled;
  final ValueChanged<CatalogEntry> onPick;

  /// «Crear proveedor», «Crear producto», «Agregar persona»… Nulo si esta
  /// pantalla no ofrece el alta.
  final String? createLabel;
  final Future<CatalogEntry?> Function()? onCreate;

  /// Muestra la unidad de cada producto en la hoja, como el formulario.
  final bool showUnit;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      ...field.candidates,
      for (final e in entries)
        if (!field.candidates.contains(e)) e,
    ];
    final selected = field.isResolved && ordered.contains(field.value)
        ? field.value
        : null;
    String secondary(CatalogEntry e) => [
      if (field.candidates.contains(e)) 'Parecido a lo dictado',
      if (showUnit && e.unit != null) e.unit!.code,
    ].join(' · ');
    final hasSecondary = ordered.any((e) => secondary(e).isNotEmpty);
    return AdaptiveEntityPicker<CatalogEntry>(
      label: label,
      items: ordered,
      value: selected,
      labelOf: (e) => e.name,
      secondaryOf: hasSecondary ? secondary : null,
      enabled: enabled,
      allowClear: false,
      autoSelectSingle: false,
      emptyMessage: 'No hay opciones en el catálogo.',
      createLabel: enabled ? createLabel : null,
      onCreate: enabled ? onCreate : null,
      onChanged: (value) {
        if (value != null) onPick(value);
      },
    );
  }
}
