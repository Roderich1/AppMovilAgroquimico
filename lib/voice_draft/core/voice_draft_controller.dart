/// Patrón común de borrador de voz (#16, F09-VOZ-08): vista previa, edición,
/// confirmación única y descarte, igual para compra, planificación y
/// aplicación.
///
/// Reglas que viven **aquí y sólo aquí**:
///
/// 1. La voz y la edición manual sólo cambian el borrador en memoria.
/// 2. Una edición manual no la sobrescribe un resultado de voz posterior o
///    tardío: el parche se descarta campo a campo y se cuenta.
/// 3. Confirmar exige un borrador sin bloqueos y llama a [commit] **una sola
///    vez**, aunque lleguen dos toques o un callback durante la escritura.
/// 4. Después de confirmar, descartar o liberar, la voz ya no cambia nada.
/// 5. Si la escritura falla, el borrador se conserva editable y no se
///    reintenta solo.
///
/// [commit] es el caso de uso manual existente (`confirmPurchase`,
/// `addPlanMulti` o `confirmApplication`), inyectado por la capa de
/// presentación. Este archivo no conoce la base de datos.
library;

import 'package:flutter/foundation.dart';

import 'draft_field.dart';

/// Un borrador tipado inmutable.
abstract interface class VoiceDraft<Self extends VoiceDraft<Self>> {
  /// Motivos que impiden confirmar, en palabras del usuario. Vacío = válido.
  List<String> get blockers;
}

enum DraftPhase {
  /// Se puede dictar, editar, confirmar o descartar.
  editing,

  /// La escritura está en curso: nada más entra.
  confirming,

  /// Escrito una vez. El borrador queda cerrado.
  confirmed,

  /// Cancelado o liberado sin escribir.
  discarded,
}

class VoiceDraftController<D extends VoiceDraft<D>, R> extends ChangeNotifier {
  VoiceDraftController({
    required D initial,
    required Future<R> Function(D draft) commit,
    String Function(Object error)? describeError,
  }) : _draft = initial,
       _commit = commit,
       _describeError = describeError ?? _defaultError;

  D _draft;
  final Future<R> Function(D draft) _commit;
  final String Function(Object error) _describeError;

  DraftPhase _phase = DraftPhase.editing;
  R? _result;
  String? _error;
  int _commitCalls = 0;
  int _ignoredVoicePatches = 0;
  int _keptManual = 0;
  bool _disposed = false;

  D get draft => _draft;
  DraftPhase get phase => _phase;

  /// Identificador o resultado devuelto por el caso de uso tras confirmar.
  R? get result => _result;

  /// Error de la última escritura, si falló. El borrador sigue editable.
  String? get error => _error;

  /// Cuántas veces se llamó al caso de uso. Debe ser 0 o 1.
  int get commitCalls => _commitCalls;

  /// Parches de voz que llegaron cuando el borrador ya no aceptaba cambios.
  int get ignoredVoicePatches => _ignoredVoicePatches;

  /// Campos que la voz quiso cambiar y se conservaron por ser manuales.
  int get keptManualFields => _keptManual;

  List<String> get blockers => _draft.blockers;

  bool get canConfirm => _phase == DraftPhase.editing && blockers.isEmpty;

  /// Aplica un resultado de voz ya interpretado. Devuelve `false` si se
  /// descartó entero por llegar tarde (confirmando, confirmado o descartado).
  bool applyVoice((D, VoicePatchOutcome) Function(D current) patch) {
    if (_phase != DraftPhase.editing) {
      _ignoredVoicePatches++;
      return false;
    }
    final (next, outcome) = patch(_draft);
    _keptManual += outcome.keptManual;
    _draft = next;
    _error = null;
    _notify();
    return true;
  }

  /// Aplica una edición manual. Fuera de edición no hace nada.
  bool editManually(D Function(D current) edit) {
    if (_phase != DraftPhase.editing) return false;
    _draft = edit(_draft);
    _error = null;
    _notify();
    return true;
  }

  /// Confirmación táctil única. Devuelve el resultado sólo a la llamada que
  /// escribió; las demás reciben `null` sin escribir.
  Future<R?> confirm() async {
    if (_phase != DraftPhase.editing || blockers.isNotEmpty) return null;
    _phase = DraftPhase.confirming;
    _error = null;
    _notify();
    final snapshot = _draft;
    try {
      _commitCalls++;
      final value = await _commit(snapshot);
      _result = value;
      _phase = DraftPhase.confirmed;
      _notify();
      return value;
    } catch (error) {
      _error = _describeError(error);
      _phase = _disposed ? DraftPhase.discarded : DraftPhase.editing;
      _notify();
      return null;
    }
  }

  /// Cancelar: descarta el borrador sin escribir. No interrumpe una
  /// escritura en curso (la transacción del dominio es atómica); en ese caso
  /// no hace nada y la escritura termina su curso.
  bool discard() {
    if (_phase != DraftPhase.editing) return false;
    _phase = DraftPhase.discarded;
    _notify();
    return true;
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (_phase == DraftPhase.editing) _phase = DraftPhase.discarded;
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static String _defaultError(Object error) =>
      'No se pudo registrar. El borrador se conserva sin cambios en la base.';
}
