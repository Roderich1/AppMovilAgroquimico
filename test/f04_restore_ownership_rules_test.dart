// Regla pura de propiedad de una copia y exclusión de sustitución.
import 'dart:async';

import 'package:agroquimicos/data/database_replacement.dart';
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:agroquimicos/domain/restore_ownership.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/f04_mode_fixtures.dart';

BackupOwnership _bound(OwnerScope scope, {String? at}) => BackupOwnership(
  origin: InstallOrigin.newUnderPolicy,
  binding: scope,
  activatedInstallationRef: at ?? installationElsewhere,
);

RestoreContext _context({
  OwnerScope? current = memberA,
  LocalSessionCondition session = LocalSessionCondition.readable,
  OwnerScope? sessionScope = memberA,
}) => RestoreContext(
  currentBinding: current,
  session: session,
  sessionScope: sessionScope,
  currentInstallationRef: installationHere,
);

void main() {
  group('evaluateRestoreOwnership', () {
    test('misma cuenta con sesión legible: aceptada y queda activada', () {
      final verdict = evaluateRestoreOwnership(_bound(memberA), _context());
      expect(verdict.accepted, isTrue);
      expect(verdict.predicted, InstallationAccessState.activated);
    });

    test('otro Member u otro tenant que el vínculo actual: rechazada', () {
      for (final other in [memberB, memberAOtherTenant]) {
        // Aunque no haya sesión legible: el vínculo actual basta para saberlo.
        for (final session in LocalSessionCondition.values) {
          final verdict = evaluateRestoreOwnership(
            _bound(other),
            _context(session: session, sessionScope: memberA),
          );
          expect(verdict.rejection, RestoreRejection.otherOwner);
        }
      }
    });

    test('sin vínculo actual: decide la sesión legible', () {
      expect(
        evaluateRestoreOwnership(
          _bound(memberA),
          _context(current: null, sessionScope: memberB),
        ).rejection,
        RestoreRejection.otherOwner,
      );
      expect(
        evaluateRestoreOwnership(
          _bound(memberA),
          _context(current: null),
        ).predicted,
        InstallationAccessState.activated,
      );
    });

    test('sin sesión legible no se demuestra identidad: exige reactivar', () {
      final verdict = evaluateRestoreOwnership(
        _bound(memberA),
        _context(session: LocalSessionCondition.absent, sessionScope: null),
      );
      expect(
        verdict.predicted,
        InstallationAccessState.restoredRequiresActivation,
      );
    });

    test('copia histórica: aceptada como histórica, sin titular', () {
      final verdict = evaluateRestoreOwnership(
        const BackupOwnership.historical(),
        _context(),
      );
      expect(verdict.predicted, InstallationAccessState.legacyUnbound);
    });

    test('copia nueva sin titular: activación incompleta, rechazada', () {
      for (final session in LocalSessionCondition.values) {
        final verdict = evaluateRestoreOwnership(
          const BackupOwnership(
            origin: InstallOrigin.newUnderPolicy,
            binding: null,
            activatedInstallationRef: null,
          ),
          _context(session: session),
        );
        expect(verdict.rejection, RestoreRejection.incompleteActivation);
      }
    });

    test('el ámbito de una sesión no legible se ignora', () {
      final verdict = evaluateRestoreOwnership(
        _bound(memberA),
        _context(
          current: null,
          session: LocalSessionCondition.unreadable,
          sessionScope: memberB,
        ),
      );
      expect(verdict.accepted, isTrue);
      expect(
        verdict.predicted,
        InstallationAccessState.restoredRequiresActivation,
      );
    });
  });

  group('DatabaseReplacementGuard', () {
    test(
      'rechaza escrituras durante la sustitución y admite las internas',
      () async {
        final guard = DatabaseReplacementGuard();
        // Zona de la prueba: fuera de la sustitución, sin su marca.
        final outside = Zone.current;
        Object? fromOutside;
        Object? inside;
        await guard.replace(() async {
          await outside.run(
            () => guard
                .write(() async => 1)
                .then<void>(
                  (_) {},
                  onError: (Object e) {
                    fromOutside = e;
                  },
                ),
          );
          inside = await guard.write(() async => 'interna');
          // Una sustitución anidada se ejecuta dentro de la misma.
          expect(await guard.replace(() async => 'anidada'), 'anidada');
        });
        expect(fromOutside, isA<DatabaseReplacementInProgressException>());
        expect(inside, 'interna');
        expect(guard.isReplacing, isFalse);
        expect(await guard.write(() async => 2), 2);
      },
    );

    test('espera a las escrituras en curso antes de sustituir', () async {
      final guard = DatabaseReplacementGuard();
      final release = Completer<void>();
      final events = <String>[];
      final write = guard.write(() async {
        await release.future;
        events.add('escritura');
      });
      final replace = guard.replace(() async => events.add('sustitución'));
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty, reason: 'la sustitución espera');
      release.complete();
      await Future.wait([write, replace]);
      expect(events, ['escritura', 'sustitución']);
    });

    test('las lecturas esperan a que termine la sustitución', () async {
      final guard = DatabaseReplacementGuard();
      // Zona de la prueba: fuera de la sustitución, sin su marca.
      final outside = Zone.current;
      final release = Completer<void>();
      final events = <String>[];
      final replace = guard.replace(() async {
        await release.future;
        events.add('sustitución');
      });
      final read = outside.run(
        () => guard.whenReadable().then((_) => events.add('lectura')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      release.complete();
      await Future.wait([replace, read]);
      expect(events, ['sustitución', 'lectura']);
    });

    test('no se sustituye desde una escritura ni dos veces a la vez', () async {
      final guard = DatabaseReplacementGuard();
      // Zona de la prueba: fuera de la sustitución, sin su marca.
      final outside = Zone.current;
      await expectLater(
        guard.write(() => guard.replace(() async {})),
        throwsA(isA<StateError>()),
      );
      final release = Completer<void>();
      final first = guard.replace(() => release.future);
      await expectLater(
        outside.run(() => guard.replace(() async {})),
        throwsA(isA<DatabaseReplacementInProgressException>()),
      );
      release.complete();
      await first;
      // Un fallo dentro libera la exclusión.
      await expectLater(
        guard.replace(() async => throw StateError('x')),
        throwsA(isA<StateError>()),
      );
      expect(guard.isReplacing, isFalse);
    });
  });
}
