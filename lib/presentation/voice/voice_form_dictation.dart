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

import '../theme/agro_theme.dart';
import '../widgets/agro_ui.dart';

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

  /// Revisiones y elecciones que planteó el dictado de [_last]: «Deshacer
  /// último dictado» las retira con él (antes quedaban pendientes y, p. ej.,
  /// el precio de un dictado deshecho seguía «por revisar»; 2026-11-12).
  Set<SlotRef> _lastPending = const {};

  /// Dictados que llegaron al final (con o sin cambios). La pantalla lo usa
  /// para cerrar el panel y mostrar el resultado; no cambia ninguna regla.
  int _completions = 0;
  int get completions => _completions;

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
    _completions++;
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
    if (plan.changes.isNotEmpty || plan.newLines.isNotEmpty) {
      _last = DictationRecord(changes: plan.changes, createdLines: created);
      _lastPending = {
        for (final r in plan.reviews) r.slot,
        for (final c in plan.choices) c.slot,
      };
    }
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
      if (pending > 0) 'Revise los campos marcados.',
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
      ..._lastPending,
    };
    for (final slot in _lastPending) {
      _reviewBase.remove(slot);
      _marks.remove(slot);
    }
    _choices.removeWhere(
      (s, _) => touched.contains(s) || record.createdLines.containsKey(s.line),
    );
    _reviews.removeWhere(
      (s, _) => touched.contains(s) || record.createdLines.containsKey(s.line),
    );
    _last = null;
    _lastPending = const {};
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

/// Panel «Completar por voz» (rediseño 2026-11-12): hablar, terminar,
/// cancelar, estado, errores y deshacer. No contiene campos ni muestra lo
/// oído: lo dictado aparece en el formulario cuando el motor termina.
///
/// [docked] lo dibuja anclado abajo, con esquinas superiores redondeadas
/// (compra); si no, como una tarjeta dentro del formulario.
///
/// Una sola presentación en ambos modos (decisión A del autor, 2026-11-13):
/// «Escuchando» y «Procesando tu voz» usan la hoja de las láminas I-13 e
/// I-14 tanto en el modo individual como en el modo con varias personas;
/// lo que cambia por modo es sólo la guía [listeningHint] que pasa cada
/// formulario.
class VoiceFormPanel extends StatelessWidget {
  const VoiceFormPanel({
    super.key,
    required this.dictation,
    required this.listeningHint,
    this.engineHint,
    this.example,
    this.onClose,
    this.diagnostics,
    this.docked = false,
  });

  final VoiceFormDictation<dynamic> dictation;

  /// Guía de lo que se dicta en este formulario mientras se escucha («Diga
  /// producto, cantidad y precio»). «Escuchando» se muestra en la hoja oscura
  /// con esta guía y «Cancelar» / «Terminar» lado a lado; «Procesando tu voz»
  /// dice que los datos aparecerán para revisarlos. Sólo presentación: el
  /// dictado, sus fases y sus botones son los mismos en ambos modos.
  final String listeningHint;

  /// Instrumentos de diagnóstico del motor. Sólo los pasa la compilación de
  /// diagnóstico (`AGRO_VOICE_DIAG=true`); en la de presentación es nulo.
  final Widget? diagnostics;

  /// Cómo se dicta con este motor, sin nombres técnicos.
  final String? engineHint;

  /// Frase de ejemplo («Diga, por ejemplo …»). Es sólo una guía.
  final String? example;
  final VoidCallback? onClose;
  final bool docked;

  static const _bigLabel = TextStyle(
    fontFamily: AgroFonts.body,
    fontSize: 18,
    fontWeight: FontWeight.w700,
  );

  /// «Escuchando» y «Procesando tu voz» (láminas I-13 e I-14), en ambos modos.
  Widget _busy(BuildContext context, VoiceFormDictation<dynamic> d) {
    final recording = d.phase == VoiceFormPhase.recording;
    final onInk = recording ? Colors.white : AgroColors.ink;
    final soft = recording ? AgroColors.onInk : AgroColors.muted;
    final cancel = OutlinedButton(
      key: const Key('voz-cancelar-dictado'),
      onPressed: d.cancel,
      style: OutlinedButton.styleFrom(
        foregroundColor: onInk,
        side: BorderSide(color: recording ? AgroColors.onInk : AgroColors.ink),
        minimumSize: const Size(0, 56),
        textStyle: _bigLabel,
        shape: const StadiumBorder(),
      ),
      child: const Text('Cancelar'),
    );
    final terminate = FilledButton(
      key: const Key('voz-terminar'),
      onPressed: d.finish,
      style: FilledButton.styleFrom(
        backgroundColor: AgroColors.lime,
        foregroundColor: AgroColors.ink,
        minimumSize: const Size(0, 56),
        textStyle: _bigLabel,
      ),
      child: const Text('Terminar'),
    );
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 13;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: recording ? AgroColors.lime : AgroColors.chip,
                shape: BoxShape.circle,
              ),
              child: recording
                  ? const Icon(Icons.mic, color: AgroColors.ink)
                  : const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AgroColors.ink,
                        semanticsLabel: 'Procesando lo dictado',
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recording ? 'Escuchando' : 'Procesando tu voz',
                      key: const Key('voz-panel-estado'),
                      style: AgroText.h2.copyWith(color: onInk),
                    ),
                    Text(
                      recording
                          ? listeningHint
                          : 'Los datos aparecerán en el formulario para que '
                                'los revise.',
                      key: const Key('voz-panel-guia'),
                      style: AgroText.detail.copyWith(color: soft),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (recording && stacked) ...[
          // Letra grande: uno sobre otro, para que «Cancelar» no se parta.
          terminate,
          const SizedBox(height: 10),
          cancel,
        ] else if (recording)
          Row(
            children: [
              Expanded(flex: 2, child: cancel),
              const SizedBox(width: 10),
              Expanded(flex: 3, child: terminate),
            ],
          )
        else
          cancel,
        const SizedBox(height: 10),
        Text(
          recording
              ? 'Nada se guarda solo: usted revisa y confirma.'
              : 'Lo que ya escribió a mano se conserva.',
          textAlign: TextAlign.center,
          style: AgroText.label.copyWith(color: soft),
        ),
        if (diagnostics != null) ...[const Divider(), diagnostics!],
      ],
    );
    final background = recording ? AgroColors.ink : AgroColors.surface;
    if (!docked) {
      return Container(
        key: const Key('voz-panel'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: content,
      );
    }
    return Semantics(
      key: const Key('voz-panel'),
      container: true,
      label: 'Completar por voz',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2E0F2A1D),
              blurRadius: 24,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: recording ? AgroColors.inkSoft : AgroColors.handle,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                content,
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: dictation,
    builder: (context, _) {
      final d = dictation;
      if (d.phase == VoiceFormPhase.recording ||
          d.phase == VoiceFormPhase.processing) {
        return _busy(context, d);
      }
      // Desde aquí sólo «Abriendo el micrófono…» y listo para dictar.
      final (icon, status, mic) = switch (d.phase) {
        VoiceFormPhase.recording ||
        VoiceFormPhase.processing ||
        VoiceFormPhase.opening => (
          Icons.mic_none,
          'Abriendo el micrófono…',
          'Espere un momento',
        ),
        VoiceFormPhase.ready when d.hasPending => (
          Icons.rule,
          'Revise los campos marcados',
          'Micrófono apagado',
        ),
        VoiceFormPhase.ready => (
          Icons.mic_none,
          'Completar por voz',
          'Micrófono apagado',
        ),
      };
      final denied =
          d.errorStatus == VoiceSessionStatus.permissionPermanentlyDenied;
      final content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AgroColors.chip,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AgroColors.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status,
                        key: const Key('voz-panel-estado'),
                        style: AgroText.h2,
                      ),
                      Text(mic, style: AgroText.detail),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (d.busy)
                TextButton(
                  key: const Key('voz-cancelar-dictado'),
                  onPressed: d.cancel,
                  style: TextButton.styleFrom(
                    backgroundColor: AgroColors.canvas,
                    foregroundColor: AgroColors.ink,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Cancelar'),
                )
              else if (onClose != null)
                CircleIconButton(
                  key: const Key('voz-panel-cerrar'),
                  icon: Icons.close,
                  tooltip: 'Ocultar el panel de voz',
                  onPressed: onClose,
                  background: AgroColors.canvas,
                ),
            ],
          ),
          if (d.phase == VoiceFormPhase.ready &&
              d.message == null &&
              (example != null || engineHint != null)) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: AgroColors.canvas,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (example != null) ...[
                    const Text('Diga, por ejemplo', style: AgroText.label),
                    Text(
                      example!,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 21 / 15,
                        fontWeight: FontWeight.w500,
                        color: AgroColors.ink,
                      ),
                    ),
                  ],
                  if (engineHint != null)
                    Padding(
                      padding: EdgeInsets.only(top: example == null ? 0 : 6),
                      child: Text(engineHint!, style: AgroText.detail),
                    ),
                ],
              ),
            ),
          ],
          if (d.message != null) ...[
            const SizedBox(height: 10),
            _MessageLine(
              textKey: const Key('voz-panel-mensaje'),
              text: d.message!,
              error: d.messageIsError,
            ),
          ],
          for (final (i, notice) in d.notices.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _MessageLine(
                textKey: Key('voz-panel-aviso-$i'),
                text: notice,
                notice: true,
              ),
            ),
          const SizedBox(height: 12),
          if (!d.busy)
            FilledButton.icon(
              key: const Key('voz-hablar'),
              onPressed: d.start,
              style: FilledButton.styleFrom(
                backgroundColor: AgroColors.lime,
                foregroundColor: AgroColors.ink,
                minimumSize: const Size.fromHeight(60),
                textStyle: _bigLabel,
              ),
              icon: const Icon(Icons.mic),
              label: const Text('Hablar'),
            ),
          if (d.canUndo || denied)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                if (d.canUndo)
                  TextButton.icon(
                    key: const Key('voz-deshacer'),
                    onPressed: d.undoLast,
                    icon: const Icon(Icons.undo),
                    label: const Text('Deshacer último dictado'),
                  ),
                if (denied)
                  TextButton(
                    key: const Key('voz-ajustes'),
                    onPressed: d.session.openSystemSettings,
                    child: const Text('Abrir ajustes'),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          const Text(
            'Nada se guarda solo: usted revisa y confirma.',
            textAlign: TextAlign.center,
            style: AgroText.label,
          ),
          if (diagnostics != null) ...[const Divider(), diagnostics!],
        ],
      );
      if (!docked) {
        return Container(
          key: const Key('voz-panel'),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: AgroColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: content,
        );
      }
      return Semantics(
        key: const Key('voz-panel'),
        container: true,
        label: 'Completar por voz',
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: AgroColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Color(0x2E0F2A1D),
                blurRadius: 24,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.6,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: AgroColors.handle,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    content,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Resultado del último dictado cuando el panel ya se cerró: lo que hizo la
/// voz, los avisos, «Dictar más» y «Deshacer último dictado».
///
/// Presentación de la lámina I-15 en ambos modos (decisión A del autor,
/// 2026-11-13): «Dictar más» en lima y «Deshacer último dictado» como botón
/// contorneado, lado a lado; los avisos (lo que no se usó) van en un
/// recuadro aparte, debajo. Un mensaje de error lleva su icono.
class VoiceResultBanner extends StatelessWidget {
  const VoiceResultBanner({
    super.key,
    required this.dictation,
    required this.onDictateMore,
    this.onDismiss,
  });

  final VoiceFormDictation<dynamic> dictation;
  final VoidCallback? onDictateMore;
  final VoidCallback? onDismiss;

  static const _onInk = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    color: Colors.white,
  );

  Widget _banner(VoiceFormDictation<dynamic> d, String message) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        key: const Key('voz-resultado'),
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        decoration: BoxDecoration(
          color: AgroColors.ink,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (d.messageIsError) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.error_outline,
                      color: AgroColors.lime,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      key: const Key('voz-panel-mensaje'),
                      style: _onInk.copyWith(
                        fontSize: 16,
                        height: 22 / 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    key: const Key('voz-resultado-cerrar'),
                    tooltip: 'Ocultar este aviso',
                    onPressed: onDismiss,
                    color: AgroColors.onInk,
                    icon: const Icon(Icons.close, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: const Key('voz-dictar-mas'),
                    onPressed: onDictateMore,
                    style: FilledButton.styleFrom(
                      backgroundColor: AgroColors.lime,
                      foregroundColor: AgroColors.ink,
                      minimumSize: const Size(0, 44),
                    ),
                    child: const Text('Dictar más'),
                  ),
                  if (d.canUndo)
                    OutlinedButton(
                      key: const Key('voz-deshacer'),
                      onPressed: d.undoLast,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AgroColors.onInk),
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text('Deshacer último dictado'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      for (final (i, notice) in d.notices.indexed)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: AgroColors.track,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: AgroColors.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    notice,
                    key: Key('voz-panel-aviso-$i'),
                    style: const TextStyle(
                      fontSize: 15,
                      height: 21 / 15,
                      color: AgroColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: dictation,
    builder: (context, _) {
      final d = dictation;
      final pending = d.pendingCount == 1
          ? 'Queda 1 campo dictado por revisar.'
          : 'Quedan ${d.pendingCount} campos dictados por revisar.';
      final message = d.message ?? (d.hasPending ? pending : 'Dictado listo.');
      return _banner(d, message);
    },
  );
}

class _MessageLine extends StatelessWidget {
  const _MessageLine({
    required this.textKey,
    required this.text,
    this.error = false,
    this.notice = false,
  });
  final Key textKey;
  final String text;
  final bool error;
  final bool notice;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        error
            ? Icons.error_outline
            : notice
            ? Icons.report_gmailerrorred_outlined
            : Icons.info_outline,
        size: 18,
        color: error
            ? AgroColors.danger
            : notice
            ? AgroColors.caution
            : AgroColors.muted,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          key: textKey,
          style: const TextStyle(
            fontSize: 14,
            height: 20 / 14,
            color: AgroColors.ink,
          ),
        ),
      ),
    ],
  );
}

/// Etiqueta «Por voz» o «Confirmado» de un campo cuyo valor sigue siendo el
/// que dejó un dictado; nada si no.
class VoiceMarkBadge extends StatelessWidget {
  const VoiceMarkBadge({
    super.key,
    required this.dictation,
    required this.slot,
    required this.current,
  });
  final VoiceFormDictation<dynamic>? dictation;
  final SlotRef slot;
  final Object? current;

  @override
  Widget build(BuildContext context) {
    final d = dictation;
    if (d == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final mark = d.markFor(slot, current);
        if (mark == null) return const SizedBox.shrink();
        final confirmed = mark.kind == VoiceMarkKind.confirmed;
        return StatusBadge(
          key: Key('voz-marca-$slot'),
          label: confirmed ? 'Confirmado' : 'Por voz',
          tone: BadgeTone.voice,
        );
      },
    );
  }
}

/// Estado de un campo tocado por un dictado, junto al campo: lo que hay que
/// elegir o revisar (con texto e icono, no sólo color) y, si [showMark],
/// «Por voz» o «Confirmado».
///
/// En una revisión se puede elegir una de las opciones que dio el
/// intérprete, escribir otro valor ([onWriteOther]: lleva al campo) o
/// descartar lo dictado. No se inventan opciones.
class VoiceSlotMark extends StatelessWidget {
  const VoiceSlotMark({
    super.key,
    required this.dictation,
    required this.slot,
    required this.current,
    this.currentDisplay,
    this.onWriteOther,
    this.writeOtherLabel = 'Escribir otro valor',
    this.showMark = true,
  });

  final VoiceFormDictation<dynamic>? dictation;
  final SlotRef slot;
  final Object? current;

  /// Cómo se muestra el valor actual en una elección («Agro DEMO»).
  final String? currentDisplay;
  final VoidCallback? onWriteOther;
  final String writeOtherLabel;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final d = dictation;
    if (d == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final choice = d.choiceFor(slot);
        if (choice != null) {
          return _Box(
            key: Key('voz-elegir-$slot'),
            icon: Icons.call_split,
            label: 'Elegir',
            message:
                'El dictado dice «${choice.proposedDisplay}»; el formulario '
                'tiene ${currentDisplay == null ? 'otro valor' : '«$currentDisplay»'}.',
            actions: [
              _option(
                Key('voz-mantener-$slot'),
                'Mantener',
                () => d.resolveChoice(slot, useDictated: false),
              ),
              _option(
                Key('voz-usar-$slot'),
                'Usar lo dictado',
                () => d.resolveChoice(slot, useDictated: true),
                strong: true,
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
            message: review.review.message,
            actions: [
              for (final (i, o) in review.review.options.indexed)
                Tooltip(
                  message: o.hint ?? o.label,
                  child: _option(
                    Key('voz-opcion-$slot-$i'),
                    o.label,
                    o.enabled ? () => d.resolveReview(slot, o) : null,
                  ),
                ),
              if (onWriteOther != null)
                _option(
                  Key('voz-escribir-$slot'),
                  writeOtherLabel,
                  onWriteOther,
                  icon: Icons.edit_outlined,
                ),
              TextButton(
                key: Key('voz-descartar-$slot'),
                onPressed: () => d.resolveReview(slot, null),
                style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                child: const Text('Descartar lo dictado'),
              ),
            ],
          );
        }
        if (!showMark) return const SizedBox.shrink();
        final mark = d.markFor(slot, current);
        if (mark == null) return const SizedBox.shrink();
        final confirmed = mark.kind == VoiceMarkKind.confirmed;
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(
              key: Key('voz-marca-$slot'),
              label: confirmed ? 'Confirmado' : 'Por voz',
              tone: BadgeTone.voice,
            ),
          ),
        );
      },
    );
  }

  static Widget _option(
    Key key,
    String label,
    VoidCallback? onPressed, {
    bool strong = false,
    IconData? icon,
  }) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      backgroundColor: strong ? AgroColors.ink : null,
      foregroundColor: strong ? Colors.white : AgroColors.ink,
    );
    return icon == null
        ? OutlinedButton(
            key: key,
            onPressed: onPressed,
            style: style,
            child: Text(label),
          )
        : OutlinedButton.icon(
            key: key,
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    super.key,
    required this.icon,
    required this.label,
    required this.message,
    required this.actions,
  });
  final IconData icon;
  final String label;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4DE),
      border: Border.all(color: const Color(0xFFC77700), width: 1.5),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusBadge(label: label, tone: BadgeTone.review),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AgroColors.warnInk),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  color: AgroColors.warnInk,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    ),
  );
}

/// «Falta», sin depender del color, para un campo obligatorio vacío de una
/// línea tocada por la voz.
class VoiceMissingMark extends StatelessWidget {
  const VoiceMissingMark({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Align(
      alignment: Alignment.centerLeft,
      child: StatusBadge(label: 'Falta: $label', tone: BadgeTone.missing),
    ),
  );
}
