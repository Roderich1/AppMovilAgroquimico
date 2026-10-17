/// Piezas comunes de las pantallas de borrador por voz (#16): el mismo
/// aviso, el mismo estado por campo, la misma elección contra el catálogo, los
/// mismos bloqueos y el mismo tratamiento de lo dictado en compra,
/// planificación y aplicación.
library;

import 'package:flutter/material.dart';

import '../../voice_draft/catalog/voice_catalog.dart';
import '../../voice_draft/core/draft_field.dart';
import '../../voice_draft/interpretation/voice_intent.dart';

/// Lleva la cuenta del texto cerrado ya interpretado de una sesión de voz y
/// entrega **sólo lo nuevo**. Lo provisional nunca pasa por aquí: sólo el
/// texto que la sesión ya cerró (`committedText`).
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

/// Aviso común: la voz sólo prepara un borrador.
class VoiceDraftNotice extends StatelessWidget {
  const VoiceDraftNotice({
    super.key,
    required this.confirmLabel,
    required this.catalogs,
  });

  /// Texto del botón que registra («Registrar compra»).
  final String confirmLabel;

  /// Qué se busca en los catálogos («Los productos, proveedores y personas»).
  final String catalogs;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        'La voz sólo prepara un borrador. Nada se registra hasta que usted '
        'revise y pulse «$confirmLabel». Lo que corrija a mano no lo cambia '
        'la voz. $catalogs se buscan en sus catálogos; si falta uno, créelo '
        'antes en Catálogos.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ),
  );
}

/// Lo dictado que ya se aplicó al borrador (lo «refinado»).
class VoiceAppliedPanel extends StatelessWidget {
  const VoiceAppliedPanel({super.key, required this.applied});
  final List<String> applied;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('voz-aplicado'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ya aplicado al borrador',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        for (final text in applied.reversed.take(3)) Text('«$text»'),
      ],
    ),
  );
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
  });

  final String label;
  final DraftField<Object?> field;
  final Widget child;

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
              Expanded(child: Text(label)),
              Text(text, style: TextStyle(color: color)),
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

/// Elegir una entrada **existente** del catálogo. Las opciones del campo
/// ambiguo van primero.
class CatalogEntryPicker extends StatelessWidget {
  const CatalogEntryPicker({
    super.key,
    required this.entries,
    required this.field,
    required this.enabled,
    required this.onPick,
  });

  final List<CatalogEntry> entries;
  final DraftField<CatalogEntry> field;
  final bool enabled;
  final ValueChanged<CatalogEntry> onPick;

  @override
  Widget build(BuildContext context) {
    final ordered = [
      ...field.candidates,
      for (final e in entries)
        if (!field.candidates.contains(e)) e,
    ];
    final selected = field.isResolved ? field.value : null;
    return DropdownButton<CatalogEntry>(
      isExpanded: true,
      value: ordered.contains(selected) ? selected : null,
      hint: const Text('Elegir'),
      items: [
        for (final e in ordered)
          DropdownMenuItem(value: e, child: Text(e.name)),
      ],
      onChanged: enabled
          ? (value) {
              if (value != null) onPick(value);
            }
          : null,
    );
  }
}
