// Clasificación de la instalación (RF-01, CU-01; v1.5 §3.11.6). Reglas puras.
import 'package:agroquimicos/domain/installation_access.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/f04_mode_fixtures.dart';

void main() {
  InstallationAccessState classify({
    InstallOrigin origin = InstallOrigin.newUnderPolicy,
    OwnerScope? binding,
    String? activatedRef,
    String? currentRef,
    LocalSessionCondition session = LocalSessionCondition.absent,
    OwnerScope? sessionScope,
  }) => classifyInstallation(
    InstallationAccessInputs(
      origin: origin,
      activeBinding: binding,
      activatedInstallationRef: activatedRef,
      currentInstallationRef: currentRef ?? installationHere,
      session: session,
      sessionScope: sessionScope,
    ),
  );

  group('instalación nueva (base creada bajo la política)', () {
    test('sin sesión: requiere activación y bloquea operaciones', () {
      final state = classify();
      expect(state, InstallationAccessState.newRequiresActivation);
      expect(state.allowsFarmerOperations, isFalse);
    });

    test('activada en línea pero sin titular: activación incompleta', () {
      final state = classify(
        session: LocalSessionCondition.readable,
        sessionScope: memberA,
      );
      expect(state, InstallationAccessState.activationPendingOwner);
      expect(state.allowsFarmerOperations, isFalse);
      expect(state.allowsOwnerBinding, isTrue);
    });

    test('sesión ilegible sin titular: no se trata como nueva ni habilita', () {
      final state = classify(session: LocalSessionCondition.unreadable);
      expect(state, InstallationAccessState.sessionDamagedNotActivated);
      expect(state, isNot(InstallationAccessState.newRequiresActivation));
      expect(state.allowsFarmerOperations, isFalse);
    });
  });

  group('instalación previamente activada', () {
    test('sesión legible del mismo Member y tenant: activada', () {
      final state = classify(
        binding: memberA,
        activatedRef: installationHere,
        session: LocalSessionCondition.readable,
        sessionScope: memberA,
      );
      expect(state, InstallationAccessState.activated);
      expect(state.allowsFarmerOperations, isTrue);
    });

    test(
      'reapertura sin red con la sesión expirada localmente sigue operando',
      () {
        // Una sesión expirada sigue siendo legible: el ámbito se conoce.
        expect(
          classify(
            binding: memberA,
            activatedRef: installationHere,
            session: LocalSessionCondition.readable,
            sessionScope: memberA,
          ).allowsFarmerOperations,
          isTrue,
        );
      },
    );

    test(
      'sesión ilegible en la misma instalación: conserva operación local',
      () {
        final state = classify(
          binding: memberA,
          activatedRef: installationHere,
          session: LocalSessionCondition.unreadable,
        );
        expect(state, InstallationAccessState.activatedSessionUnavailable);
        expect(state.allowsFarmerOperations, isTrue);
      },
    );

    test(
      'sesión ausente en la misma instalación: conserva operación local',
      () {
        expect(
          classify(binding: memberA, activatedRef: installationHere),
          InstallationAccessState.activatedSessionUnavailable,
        );
      },
    );

    test(
      'identidad de instalación dañada (ref null): misma instalación física',
      () {
        expect(
          classifyInstallation(
            InstallationAccessInputs(
              origin: InstallOrigin.newUnderPolicy,
              activeBinding: memberA,
              activatedInstallationRef: installationHere,
              currentInstallationRef: null,
              session: LocalSessionCondition.unreadable,
              sessionScope: null,
            ),
          ),
          InstallationAccessState.activatedSessionUnavailable,
        );
      },
    );
  });

  group('datos restaurados o de otra identidad', () {
    test('vínculo de otra instalación sin sesión: exige activar de nuevo', () {
      final state = classify(
        binding: memberA,
        activatedRef: installationElsewhere,
      );
      expect(state, InstallationAccessState.restoredRequiresActivation);
      expect(state.allowsFarmerOperations, isFalse);
    });

    test(
      'vínculo de otra instalación con sesión ilegible: tampoco habilita',
      () {
        expect(
          classify(
            binding: memberA,
            activatedRef: installationElsewhere,
            session: LocalSessionCondition.unreadable,
          ),
          InstallationAccessState.restoredRequiresActivation,
        );
      },
    );

    test('sesión de otro Member: no habilita datos de otro miembro', () {
      final state = classify(
        binding: memberA,
        activatedRef: installationHere,
        session: LocalSessionCondition.readable,
        sessionScope: memberB,
      );
      expect(state, InstallationAccessState.identityMismatch);
      expect(state.allowsFarmerOperations, isFalse);
    });

    test('mismo Member en otro tenant: también es otra identidad', () {
      expect(
        classify(
          binding: memberA,
          activatedRef: installationHere,
          session: LocalSessionCondition.readable,
          sessionScope: memberAOtherTenant,
        ),
        InstallationAccessState.identityMismatch,
      );
    });

    test('reactivar con el mismo Member en otra instalación: activada', () {
      expect(
        classify(
          binding: memberA,
          activatedRef: installationElsewhere,
          session: LocalSessionCondition.readable,
          sessionScope: memberA,
        ),
        InstallationAccessState.activated,
      );
    });
  });

  group('base histórica sin vincular (compatibilidad)', () {
    for (final session in LocalSessionCondition.values) {
      test('con sesión ${session.name}: opera como antes, sin titular', () {
        final state = classify(
          origin: InstallOrigin.legacyPrePolicy,
          session: session,
          sessionScope: session == LocalSessionCondition.readable
              ? memberA
              : null,
        );
        expect(state, InstallationAccessState.legacyUnbound);
        expect(state.allowsFarmerOperations, isTrue);
        // Puede vincularse, pero sólo por elección explícita tras activar.
        expect(state.allowsOwnerBinding, isTrue);
      });
    }
  });

  test('la referencia de instalación es un resumen, no el identificador', () {
    const id = '11111111-1111-4111-8111-111111111111';
    final ref = installationReference(id);
    expect(ref, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(ref, installationReference(id));
    expect(ref, isNot(contains(id)));
    expect(ref, isNot(installationElsewhere));
  });
}
