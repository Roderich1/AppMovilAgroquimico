/// «Completar por voz» dentro de un formulario normal (F09, formulario único).
///
/// [VoiceFormDictation] es el puente entre la sesión de voz de siempre
/// ([VoiceSessionController], con el puerto que corresponda a la operación) y
/// el estado del formulario, que sigue siendo el único borrador:
///
/// 1. Al pulsar «Hablar» se toma una foto del formulario y se empieza una
///    interpretación **propia del dictado** (la «sombra»), con el intérprete
///    de la operación.
/// 2. Lo cerrado de la sesión se interpreta sobre la sombra; nada cambia en el
///    formulario mientras se graba o se procesa.
/// 3. Al terminar el turno, [planVoiceMerge] compara lo dictado con la foto y
///    con el formulario actual, y el formulario aplica el plan: completa
///    campos vacíos, añade líneas y deja por elegir o revisar lo demás.
/// 4. Cancelar el turno descarta la sombra: el formulario no cambia.
///
/// La voz nunca guarda: el formulario conserva su único botón de registro y
/// lo bloquea mientras haya un dictado en curso o algo por resolver.
library;

import 'package:flutter/material.dart';

import '../../voice/session/voice_session_controller.dart';
import '../../voice/session/voice_session_state.dart';
import '../../voice_draft/form/voice_form_merge.dart';

export '../../voice_draft/form/voice_form_merge.dart';

/// Fase visible del dictado.
enum VoiceFormPhase {
  /// Listo para dictar.
  ready,

  /// Abriendo el micrófono (permiso, motor).
  opening,

  /// Grabando.
  recording,

  /// Procesando el audio.
  processing,
}

/// Cómo quedó un campo tras un dictado (se muestra junto al campo).
enum VoiceMarkKind {
  /// Lo completó el dictado.
  added,

  /// La persona eligió o confirmó un valor que propuso el dictado.
  confirmed,
}

final class VoiceMark {
  const VoiceMark(this.kind, this.value);
  final VoiceMarkKind kind;

  /// Valor que dejó el dictado. Si el campo ya no lo tiene (la persona lo
  /// cambió), la marca deja de mostrarse.
  final Object? value;
}

/// Lo que cada formulario aporta: su foto, su intérprete y cómo se aplica un
/// plan. [S] es el tipo de la sombra (el borrador de voz de la operación).
abstract interface class VoiceFormTarget<S> {
  /// Foto actual del formulario en valores canónicos.
  FormSnapshot snapshot();

  /// Sombra vacía para un dictado nuevo, o `null` si el formulario todavía
  /// no está listo (catálogos cargando).
  S? startShadow();

  /// Interpreta [text] (sólo lo nuevo y cerrado) sobre [shadow].
  S interpret(S shadow, String text, VoiceSessionSnapshot session);

  /// Lo que dijo el dictado, en ranuras del formulario.
  VoiceProposal propose(S shadow, FormSnapshot now);

  /// Identificador para la próxima línea nueva.
  int nextLineId();

  /// Aplica un plan: cambia campos, crea líneas (con los ids del plan).
  void applyPlan(MergePlan plan);

  /// Deshace un dictado: restaura campos y quita líneas.
  void applyUndo(UndoPlan plan);

  /// Pone [value] en [slot] porque la persona lo eligió.
  void setSlot(SlotRef slot, Object? value);

  /// Nombre legible de un campo para los avisos («Proveedor», «Línea 2:
  /// precio»).
  String describeSlot(SlotRef slot);

  /// Un dictado se incorporó (para la evidencia con consentimiento).
  void onDictationApplied(S shadow, String text);
}

class VoiceFormDictation<S> extends ChangeNotifier {
  VoiceFormDictation({required this.session, required this.target}) {
    session.addListener(_onSession);
  }

  final VoiceSessionController session;
  final VoiceFormTarget<S> target;

  VoiceFormPhase _phase = VoiceFormPhase.ready;
  VoiceFormPhase get phase => _phase;

  /// Mensaje del último dictado o del último error.
  String? _message;
  String? get message => _message;
  bool _messageIsError = false;
  bool get messageIsError => _messageIsError;

  /// Avisos del intérprete del último dictado (pueden citar lo oído).
  List<String> _notices = const [];
  List<String> get notices => _notices;

  /// Error del que se puede volver (permiso, motor ocupado…).
  VoiceSessionStatus? _errorStatus;
  VoiceSessionStatus? get errorStatus => _errorStatus;

  bool _dictating = false;

  /// La sesión llegó a abrirse en este dictado (un `idle` previo no cierra
  /// nada).
  bool _opened = false;
  FormSnapshot? _before;
  S? _shadow;
  String _consumed = '';
  final _text = StringBuffer();
  bool _disposed = false;

  final Map<SlotRef, PendingChoice> _choices = {};
  final Map<SlotRef, PendingReview> _reviews = {};

  /// Valor del campo cuando se planteó cada revisión: si cambia, la persona
  /// la resolvió a mano.
  final Map<SlotRef, Object?> _reviewBase = {};
  final Map<SlotRef, VoiceMark> _marks = {};
  DictationRecord? _last;

  /// Hay un dictado en marcha (grabando o procesando).
  bool get busy => _dictating;

  /// Elecciones o revisiones pendientes de un dictado.
  bool get hasPending => _choices.isNotEmpty || _reviews.isNotEmpty;

  /// No se puede guardar: dictado en curso o algo por resolver.
  bool get blocksSave => busy || hasPending;

  int get pendingCount => _choices.length + _reviews.length;

  bool get canUndo => !busy && _last != null;

  PendingChoice? choiceFor(SlotRef slot) => _choices[slot];
  PendingReview? reviewFor(SlotRef slot) => _reviews[slot];

  /// Marca del campo si el valor sigue siendo el que dejó la voz.
  VoiceMark? markFor(SlotRef slot, Object? current) {
    final mark = _marks[slot];
    return mark != null && mark.value == current ? mark : null;
  }

  /// Hay algo de voz que mostrar en esta línea (marcas o pendientes).
  bool touchesLine(int line) =>
      _marks.keys.any((s) => s.line == line) ||
      _choices.keys.any((s) => s.line == line) ||
      _reviews.keys.any((s) => s.line == line);

  /// Motivo por el que no se puede guardar, para mostrarlo junto al botón.
  String? get saveBlockReason {
    if (busy) return 'Termine o cancele el dictado antes de continuar.';
    if (hasPending) {
      final n = pendingCount;
      return n == 1
          ? 'Hay 1 campo dictado por revisar.'
          : 'Hay $n campos dictados por revisar.';
    }
    return null;
  }

  /// «Hablar»: empieza un dictado. Nada cambia en el formulario hasta que
  /// termina.
  Future<void> start() async {
    if (_dictating || _disposed) return;
    final shadow = target.startShadow();
    if (shadow == null) {
      _setPhase(
        VoiceFormPhase.ready,
        message:
            'Espere a que termine de cargar el formulario y vuelva a '
            'pulsar «Hablar».',
      );
      return;
    }
    _dictating = true;
    _opened = false;
    _errorStatus = null;
    _before = target.snapshot();
    _shadow = shadow;
    _consumed = session.snapshot.committedText;
    _text.clear();
    _setPhase(VoiceFormPhase.opening, message: null);
    await session.startListening();
  }

  /// «Terminar»: deja de grabar; el resultado llega al procesar.
  Future<void> finish() async {
    if (!_dictating) return;
    await session.stopListening();
  }

  /// «Cancelar»: descarta la grabación o el procesamiento. Lo que ya está en
  /// el formulario (a mano o de dictados anteriores) se conserva.
  Future<void> cancel() async {
    if (!_dictating) return;
    _drop(message: 'Dictado cancelado: el formulario no cambió.');
    await session.discard();
  }

  /// El formulario se cierra: libera el micrófono sin aplicar nada.
  void release() {
    if (_dictating) _drop();
    session.handleAppPaused();
  }

  void _drop({String? message, bool error = false}) {
    _dictating = false;
    _before = null;
    _shadow = null;
    _text.clear();
    _setPhase(VoiceFormPhase.ready, message: message, error: error);
  }

  void _setPhase(
    VoiceFormPhase phase, {
    String? message,
    bool error = false,
    List<String> notices = const [],
  }) {
    _phase = phase;
    _message = message;
    _notices = notices;
    _messageIsError = error;
    if (!_disposed) notifyListeners();
  }

  static const _active = {
    VoiceSessionStatus.requestingPermission,
    VoiceSessionStatus.starting,
    VoiceSessionStatus.listening,
    VoiceSessionStatus.processing,
    VoiceSessionStatus.stopping,
  };

  void _onSession() {
    if (_disposed || !_dictating) return;
    final s = session.snapshot;
    // Sólo lo nuevo y cerrado; el texto provisional no se interpreta nunca.
    final committed = s.committedText;
    if (committed.length < _consumed.length ||
        !committed.startsWith(_consumed)) {
      _consumed = '';
    }
    final fresh = committed.substring(_consumed.length).trim();
    if (fresh.isNotEmpty && _shadow != null) {
      _shadow = target.interpret(_shadow as S, fresh, s);
      if (_text.isNotEmpty) _text.write(' ');
      _text.write(fresh);
    }
    _consumed = committed;

    if (_active.contains(s.status)) _opened = true;
    switch (s.status) {
      case VoiceSessionStatus.requestingPermission ||
          VoiceSessionStatus.starting:
        _setPhase(VoiceFormPhase.opening);
      case VoiceSessionStatus.listening:
        _setPhase(VoiceFormPhase.recording);
      case VoiceSessionStatus.processing || VoiceSessionStatus.stopping:
        _setPhase(VoiceFormPhase.processing);
      case VoiceSessionStatus.cancelled:
        _drop(message: 'Dictado cancelado: el formulario no cambió.');
      case VoiceSessionStatus.permissionDenied ||
          VoiceSessionStatus.permissionPermanentlyDenied ||
          VoiceSessionStatus.languageUnavailable ||
          VoiceSessionStatus.recognizerUnavailable ||
          VoiceSessionStatus.recoverableError ||
          VoiceSessionStatus.fatalError:
        _errorStatus = s.status;
        _drop(message: _errorMessage(s.status), error: true);
      case VoiceSessionStatus.preview || VoiceSessionStatus.idle:
        if (!_opened) return;
        if (s.reviewing > 0) {
          _setPhase(VoiceFormPhase.processing);
        } else {
          _complete();
        }
    }
  }

  static String _errorMessage(VoiceSessionStatus status) => switch (status) {
    VoiceSessionStatus.permissionDenied =>
      'Sin permiso de micrófono no se puede dictar. Puede volver a intentarlo '
          'o completar el formulario a mano.',
    VoiceSessionStatus.permissionPermanentlyDenied =>
      'El micrófono está bloqueado para esta aplicación. Actívelo en los '
          'ajustes del teléfono o complete el formulario a mano.',
    VoiceSessionStatus.languageUnavailable ||
    VoiceSessionStatus.recognizerUnavailable =>
      'La voz no está disponible en este teléfono. Complete el formulario a '
          'mano.',
    _ =>
      'No se pudo procesar el dictado. El formulario no cambió; puede volver '
          'a intentarlo.',
  };

  void _complete() {
    final shadow = _shadow;
    final before = _before;
    final text = _text.toString();
    _dictating = false;
    _before = null;
    _shadow = null;
    _text.clear();
    if (shadow == null || before == null) {
      _setPhase(VoiceFormPhase.ready);
      return;
    }
    // Libera el texto de la sesión: el próximo dictado empieza de cero.
    session.discard();
    if (text.isEmpty) {
      _setPhase(
        VoiceFormPhase.ready,
        message: 'No se oyó nada que completar. El formulario no cambió.',
      );
      return;
    }
    final now = target.snapshot();
    final plan = planVoiceMerge(
      before: before,
      now: now,
      proposal: target.propose(shadow, now),
      nextLineId: target.nextLineId(),
    );
    target.applyPlan(plan);
    for (final c in plan.changes) {
      _marks[c.slot] = VoiceMark(VoiceMarkKind.added, c.after);
      _choices.remove(c.slot);
      _reviews.remove(c.slot);
    }
    final created = <int, Map<String, Object?>>{};
    for (final line in plan.newLines) {
      created[line.line] =
          target.snapshot().line(line.line)?.fields ?? line.values;
      line.values.forEach((field, value) {
        _marks[SlotRef.line(line.line, field)] = VoiceMark(
          VoiceMarkKind.added,
          value,
        );
      });
    }
    for (final c in plan.choices) {
      _choices[c.slot] = c;
    }
    final after = target.snapshot();
    for (final r in plan.reviews) {
      _reviews[r.slot] = r;
      _reviewBase[r.slot] = after.valueOf(r.slot).$2;
    }
    _last = plan.changes.isEmpty && plan.newLines.isEmpty
        ? _last
        : DictationRecord(changes: plan.changes, createdLines: created);
    target.onDictationApplied(shadow, text);
    _setPhase(
      VoiceFormPhase.ready,
      message: _summary(plan),
      notices: plan.notices,
    );
  }

  String _summary(MergePlan plan) {
    if (plan.changesNothing) {
      final parts = <String>[
        'No cambió el formulario: no se reconoció nada que completar.',
        if (plan.keptEdited.isNotEmpty)
          'Se conservó lo que editó mientras se procesaba.',
      ];
      return parts.join(' ');
    }
    final parts = <String>[];
    final filled = plan.changes.length;
    if (filled > 0)
      parts.add(
        '$filled ${filled == 1 ? 'campo completado' : 'campos completados'}',
      );
    final lines = plan.newLines.length;
    if (lines > 0)
      parts.add('$lines ${lines == 1 ? 'línea añadida' : 'líneas añadidas'}');
    final pending = plan.choices.length + plan.reviews.length;
    if (pending > 0) parts.add('$pending por revisar');
    return [
      '${parts.join(', ')}.',
      if (pending > 0) 'Revisa los campos marcados.',
      if (plan.keptEdited.isNotEmpty)
        'Se conservó lo que editó mientras se procesaba.',
    ].join(' ');
  }

  /// La persona resuelve una elección: `useDictated` pone el valor dictado;
  /// si no, se queda el que había.
  void resolveChoice(SlotRef slot, {required bool useDictated}) {
    final c = _choices.remove(slot);
    if (c == null) return;
    if (useDictated) {
      target.setSlot(slot, c.proposed);
      _marks[slot] = VoiceMark(VoiceMarkKind.confirmed, c.proposed);
      _last = (_last ?? const DictationRecord(changes: [], createdLines: {}))
          .withChange(
            FieldChange(slot, c.current, c.proposed, c.proposedDisplay),
          );
    } else {
      _marks.remove(slot);
    }
    notifyListeners();
  }

  /// La persona elige una opción de una revisión (o la descarta con `null`).
  void resolveReview(SlotRef slot, ReviewOption? option) {
    final r = _reviews.remove(slot);
    if (r == null) return;
    if (option != null) {
      target.setSlot(slot, option.value);
      _marks[slot] = VoiceMark(VoiceMarkKind.confirmed, option.value);
      final last = _last;
      if (last != null && last.createdLines.containsKey(slot.line)) {
        _last = last.withLineValue(slot.line!, slot.field, option.value);
      } else {
        _last = (last ?? const DictationRecord(changes: [], createdLines: {}))
            .withChange(FieldChange(slot, null, option.value, option.label));
      }
    }
    notifyListeners();
  }

  /// Una revisión o elección deja de tener sentido porque la persona cambió
  /// el campo a mano: se da por resuelta con su valor.
  void slotEditedByHand(SlotRef slot) {
    final choice = _choices.remove(slot);
    final review = _reviews.remove(slot);
    if (choice != null || review != null) notifyListeners();
  }

  /// Tras una edición manual: lo pendiente cuyo campo cambió la persona queda
  /// resuelto con su valor (la voz no lo vuelve a pedir).
  void reconcile(FormSnapshot now) {
    var changed = false;
    _choices.removeWhere((slot, c) {
      final (exists, value) = now.valueOf(slot);
      final gone = !exists || value != c.current;
      changed |= gone;
      return gone;
    });
    _reviews.removeWhere((slot, _) {
      final (exists, value) = now.valueOf(slot);
      final gone = !exists || value != _reviewBase[slot];
      changed |= gone;
      return gone;
    });
    if (changed) notifyListeners();
  }

  /// La persona quitó una línea: lo pendiente de esa línea desaparece.
  void lineRemoved(int line) {
    _choices.removeWhere((s, _) => s.line == line);
    _reviews.removeWhere((s, _) => s.line == line);
    _marks.removeWhere((s, _) => s.line == line);
    notifyListeners();
  }

  /// «Deshacer último dictado»: revierte sólo lo que puso ese dictado.
  void undoLast() {
    final record = _last;
    if (record == null || busy) return;
    final plan = planVoiceUndo(record, target.snapshot());
    target.applyUndo(plan);
    for (final c in plan.restore) {
      _marks.remove(c.slot);
    }
    for (final line in plan.removeLines) {
      _marks.removeWhere((s, _) => s.line == line);
    }
    // Lo pendiente de ese dictado se retira con él.
    final touched = {
      for (final c in record.changes) c.slot,
      for (final l in record.createdLines.keys) SlotRef.line(l, '*'),
    };
    _choices.removeWhere(
      (s, _) => touched.contains(s) || record.createdLines.containsKey(s.line),
    );
    _reviews.removeWhere(
      (s, _) => touched.contains(s) || record.createdLines.containsKey(s.line),
    );
    _last = null;
    final kept = plan.keptEdited.length;
    _setPhase(
      VoiceFormPhase.ready,
      message: kept == 0
          ? 'Se deshizo el último dictado.'
          : 'Se deshizo el último dictado. Se conservó lo que editó después '
                '(${plan.keptEdited.map((s) => s.field == '*' ? 'línea ${s.line}' : target.describeSlot(s)).join(', ')}).',
    );
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_onSession);
    session.dispose();
    super.dispose();
  }
}

/// Panel compacto «Completar por voz»: hablar, terminar, cancelar, estado,
/// errores y deshacer. No contiene campos: lo dictado aparece en el
/// formulario.
class VoiceFormPanel extends StatelessWidget {
  const VoiceFormPanel({
    super.key,
    required this.dictation,
    this.engineHint,
    this.onClose,
    this.diagnostics,
  });

  final VoiceFormDictation<dynamic> dictation;

  /// Instrumentos de diagnóstico del motor. Sólo los pasa la compilación de
  /// diagnóstico (`AGRO_VOICE_DIAG=true`); en la de presentación es nulo.
  final Widget? diagnostics;

  /// Cómo se dicta con este motor («Diga la compra completa y pulse
  /// Terminar» / «Hable por frases…»), sin nombres técnicos.
  final String? engineHint;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: dictation,
    builder: (context, _) {
      final theme = Theme.of(context);
      final d = dictation;
      final (icon, status) = switch (d.phase) {
        VoiceFormPhase.opening => (Icons.mic_none, 'Abriendo el micrófono…'),
        VoiceFormPhase.recording => (Icons.mic, 'Grabando'),
        VoiceFormPhase.processing => (Icons.hourglass_top, 'Procesando tu voz'),
        VoiceFormPhase.ready when d.hasPending => (
          Icons.rule,
          'Revisa los campos marcados',
        ),
        VoiceFormPhase.ready => (Icons.mic_none, 'Listo para dictar'),
      };
      return Card(
        key: const Key('voz-panel'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        status,
                        key: const Key('voz-panel-estado'),
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ),
                  if (onClose != null && !d.busy)
                    IconButton(
                      key: const Key('voz-panel-cerrar'),
                      tooltip: 'Ocultar el panel de voz',
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              if (engineHint != null && d.phase == VoiceFormPhase.ready)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: Text(engineHint!, style: theme.textTheme.bodySmall),
                ),
              if (d.message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        d.messageIsError
                            ? Icons.error_outline
                            : Icons.info_outline,
                        size: 18,
                        color: d.messageIsError
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          d.message!,
                          key: const Key('voz-panel-mensaje'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              for (final (i, notice) in d.notices.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.report_gmailerrorred_outlined,
                        size: 18,
                        color: theme.colorScheme.tertiary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          notice,
                          key: Key('voz-panel-aviso-$i'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (!d.busy)
                    FilledButton.icon(
                      key: const Key('voz-hablar'),
                      onPressed: d.start,
                      icon: const Icon(Icons.mic),
                      label: const Text('Hablar'),
                    ),
                  if (d.phase == VoiceFormPhase.recording)
                    FilledButton.icon(
                      key: const Key('voz-terminar'),
                      onPressed: d.finish,
                      icon: const Icon(Icons.stop),
                      label: const Text('Terminar'),
                    ),
                  if (d.busy)
                    OutlinedButton.icon(
                      key: const Key('voz-cancelar-dictado'),
                      onPressed: d.cancel,
                      icon: const Icon(Icons.close),
                      label: const Text('Cancelar dictado'),
                    ),
                  if (d.canUndo)
                    TextButton.icon(
                      key: const Key('voz-deshacer'),
                      onPressed: d.undoLast,
                      icon: const Icon(Icons.undo),
                      label: const Text('Deshacer último dictado'),
                    ),
                  if (d.errorStatus ==
                      VoiceSessionStatus.permissionPermanentlyDenied)
                    TextButton(
                      key: const Key('voz-ajustes'),
                      onPressed: d.session.openSystemSettings,
                      child: const Text('Abrir ajustes'),
                    ),
                ],
              ),
              if (diagnostics != null) ...[const Divider(), diagnostics!],
            ],
          ),
        ),
      );
    },
  );
}

/// Estado de un campo tocado por un dictado, junto al campo: «Por voz»,
/// «Confirmado», o lo que hay que elegir o revisar, con texto e icono (no
/// sólo color).
class VoiceSlotMark extends StatelessWidget {
  const VoiceSlotMark({
    super.key,
    required this.dictation,
    required this.slot,
    required this.current,
    this.currentDisplay,
  });

  final VoiceFormDictation<dynamic>? dictation;
  final SlotRef slot;
  final Object? current;

  /// Cómo se muestra el valor actual en una elección («Agro DEMO»).
  final String? currentDisplay;

  @override
  Widget build(BuildContext context) {
    final d = dictation;
    if (d == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final theme = Theme.of(context);
        final small = theme.textTheme.bodySmall;
        final choice = d.choiceFor(slot);
        if (choice != null) {
          return _Box(
            key: Key('voz-elegir-$slot'),
            icon: Icons.call_split,
            label: 'Elegir',
            children: [
              Text(
                'El dictado dice «${choice.proposedDisplay}»; el formulario '
                'tiene ${currentDisplay == null ? 'otro valor' : '«$currentDisplay»'}.',
                style: small,
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    key: Key('voz-mantener-$slot'),
                    onPressed: () => d.resolveChoice(slot, useDictated: false),
                    child: const Text('Mantener'),
                  ),
                  FilledButton.tonal(
                    key: Key('voz-usar-$slot'),
                    onPressed: () => d.resolveChoice(slot, useDictated: true),
                    child: const Text('Usar lo dictado'),
                  ),
                ],
              ),
            ],
          );
        }
        final review = d.reviewFor(slot);
        if (review != null) {
          return _Box(
            key: Key('voz-revisar-$slot'),
            icon: Icons.help_outline,
            label: 'Revisar',
            children: [
              Text(review.review.message, style: small),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (i, o) in review.review.options.indexed)
                    Tooltip(
                      message: o.hint ?? o.label,
                      child: FilledButton.tonal(
                        key: Key('voz-opcion-$slot-$i'),
                        onPressed: o.enabled
                            ? () => d.resolveReview(slot, o)
                            : null,
                        child: Text(o.label),
                      ),
                    ),
                  TextButton(
                    key: Key('voz-descartar-$slot'),
                    onPressed: () => d.resolveReview(slot, null),
                    child: const Text('Descartar lo dictado'),
                  ),
                ],
              ),
            ],
          );
        }
        final mark = d.markFor(slot, current);
        if (mark == null) return const SizedBox.shrink();
        final confirmed = mark.kind == VoiceMarkKind.confirmed;
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            key: Key('voz-marca-$slot'),
            children: [
              Icon(
                confirmed ? Icons.check_circle_outline : Icons.mic_none,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                confirmed ? 'Confirmado' : 'Por voz',
                style: small?.copyWith(color: theme.colorScheme.primary),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    super.key,
    required this.icon,
    required this.label,
    required this.children,
  });
  final IconData icon;
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.tertiary),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.tertiary),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}

/// «Falta», sin depender del color, para un campo obligatorio vacío de una
/// línea tocada por la voz.
class VoiceMissingMark extends StatelessWidget {
  const VoiceMissingMark({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(
            Icons.radio_button_unchecked,
            size: 16,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 4),
          Text(
            'Falta: $label',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}
