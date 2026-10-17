import 'dart:async';

import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/core/voice_draft_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Patrón común de borrador de voz (#16, F09-VOZ-08), sin ninguna operación
/// concreta: vale igual para compra, planificación y aplicación.
final class _Draft implements VoiceDraft<_Draft> {
  const _Draft({
    this.amount = const DraftField.missing(),
    this.note = const DraftField.missing(),
  });

  final DraftField<int> amount;
  final DraftField<String> note;

  _Draft copyWith({DraftField<int>? amount, DraftField<String>? note}) =>
      _Draft(amount: amount ?? this.amount, note: note ?? this.note);

  @override
  List<String> get blockers => [
    if (!amount.isResolved) 'Falta la cantidad.',
    if (!note.isResolved) 'Falta la nota.',
  ];
}

(_Draft, VoicePatchOutcome) Function(_Draft) _voice({
  int? amount,
  String? note,
}) => (d) {
  var out = d;
  var outcome = const VoicePatchOutcome();
  if (amount != null) {
    final (f, o) = mergeField(
      out.amount,
      DraftField.resolved(amount, origin: FieldOrigin.voice),
    );
    out = out.copyWith(amount: f);
    outcome += o;
  }
  if (note != null) {
    final (f, o) = mergeField(
      out.note,
      DraftField.resolved(note, origin: FieldOrigin.voice),
    );
    out = out.copyWith(note: f);
    outcome += o;
  }
  return (out, outcome);
};

_Draft Function(_Draft) _manualAmount(int value) =>
    (d) => d.copyWith(
      amount: DraftField.resolved(value, origin: FieldOrigin.manual),
    );

void main() {
  late List<_Draft> writes;
  late VoiceDraftController<_Draft, int> controller;

  VoiceDraftController<_Draft, int> make({
    Future<int> Function(_Draft)? commit,
  }) {
    writes = [];
    return VoiceDraftController<_Draft, int>(
      initial: const _Draft(),
      commit:
          commit ??
          (draft) async {
            writes.add(draft);
            return 41;
          },
    );
  }

  setUp(() => controller = make());

  group('vista previa y bloqueos', () {
    test('un borrador incompleto no se puede confirmar ni escribe', () async {
      controller.applyVoice(_voice(amount: 5));
      expect(controller.canConfirm, isFalse);
      expect(controller.blockers, ['Falta la nota.']);
      expect(await controller.confirm(), isNull);
      expect(writes, isEmpty);
      expect(controller.commitCalls, 0);
    });

    test('voz y edición manual sólo cambian la memoria', () {
      controller.applyVoice(_voice(amount: 5, note: 'a'));
      controller.editManually(_manualAmount(7));
      expect(controller.draft.amount.value, 7);
      expect(writes, isEmpty);
    });
  });

  group('la edición manual gana a la voz tardía', () {
    test('un resultado de voz posterior no sobrescribe un campo manual', () {
      controller.applyVoice(_voice(amount: 5));
      controller.editManually(_manualAmount(7));
      controller.applyVoice(_voice(amount: 9, note: 'b'));
      expect(controller.draft.amount.value, 7);
      expect(controller.draft.amount.isManual, isTrue);
      expect(controller.draft.note.value, 'b');
      expect(controller.keptManualFields, 1);
    });
  });

  group('una sola confirmación', () {
    test('doble toque: un solo commit y un solo resultado', () async {
      controller.applyVoice(_voice(amount: 5, note: 'a'));
      final first = controller.confirm();
      final second = controller.confirm();
      expect(await first, 41);
      expect(await second, isNull);
      expect(writes, hasLength(1));
      expect(controller.commitCalls, 1);
      expect(controller.phase, DraftPhase.confirmed);
      expect(await controller.confirm(), isNull);
      expect(writes, hasLength(1));
    });

    test('un callback de voz durante la escritura no entra', () async {
      final gate = Completer<int>();
      controller = make(
        commit: (draft) {
          writes.add(draft);
          return gate.future;
        },
      );
      controller.applyVoice(_voice(amount: 5, note: 'a'));
      final pending = controller.confirm();
      expect(controller.phase, DraftPhase.confirming);
      expect(controller.applyVoice(_voice(amount: 99)), isFalse);
      expect(controller.editManually(_manualAmount(1)), isFalse);
      gate.complete(3);
      expect(await pending, 3);
      expect(writes.single.amount.value, 5);
      expect(controller.ignoredVoicePatches, 1);
    });

    test('un callback de voz después de confirmar no cambia nada', () async {
      controller.applyVoice(_voice(amount: 5, note: 'a'));
      await controller.confirm();
      expect(controller.applyVoice(_voice(amount: 6)), isFalse);
      expect(controller.draft.amount.value, 5);
    });

    test('se escribe lo que se veía al confirmar', () async {
      controller.applyVoice(_voice(amount: 5, note: 'a'));
      await controller.confirm();
      expect(writes.single.amount.value, 5);
      expect(writes.single.note.value, 'a');
    });
  });

  group('fallo de la escritura', () {
    test('conserva el borrador editable y no reintenta solo', () async {
      var calls = 0;
      controller = make(
        commit: (draft) async {
          calls++;
          throw StateError('falla');
        },
      );
      controller.applyVoice(_voice(amount: 5, note: 'a'));
      expect(await controller.confirm(), isNull);
      expect(controller.phase, DraftPhase.editing);
      expect(controller.error, isNotNull);
      expect(controller.draft.amount.value, 5);
      expect(calls, 1);
    });
  });

  group('cancelar y liberar', () {
    test('cancelar descarta sin escribir y cierra el borrador', () async {
      controller.applyVoice(_voice(amount: 5, note: 'a'));
      expect(controller.discard(), isTrue);
      expect(controller.phase, DraftPhase.discarded);
      expect(await controller.confirm(), isNull);
      expect(controller.applyVoice(_voice(amount: 1)), isFalse);
      expect(writes, isEmpty);
    });

    test('dispose sin confirmar equivale a descartar', () async {
      final c = make();
      c.applyVoice(_voice(amount: 5, note: 'a'));
      c.dispose();
      expect(c.phase, DraftPhase.discarded);
      expect(writes, isEmpty);
    });
  });
}
