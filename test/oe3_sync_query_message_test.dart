// OE3 (2026-11-03): en el POCO, «Resolver conflicto…» con una consulta real que
// devolvió 404 OPERATION_NOT_FOUND mostró «SyncQueryException(404,
// OPERATION_NOT_FOUND)». Toda consulta fallida al sindicato llega a la persona
// con un texto en español, sin el nombre de la clase ni el código técnico.
import 'package:agroquimicos/presentation/widgets/common.dart';
import 'package:agroquimicos/services/sync/sync_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('404, sin respuesta y otros estados: texto de usuario', () {
    for (final error in const [
      SyncQueryException(404, 'OPERATION_NOT_FOUND'),
      SyncQueryException(null, 'UNAVAILABLE'),
      SyncQueryException(200, 'INVALID_RESPONSE'),
      SyncQueryException(500, null),
    ]) {
      final text = friendlyError(error);
      expect(
        text,
        'No se pudo consultar al sindicato. Sus datos se conservan; '
        'inténtelo más tarde.',
      );
      expect(text, isNot(contains('SyncQueryException')));
    }
  });

  test('401 y 403: los mismos textos que la pantalla de vínculos', () {
    expect(
      friendlyError(const SyncQueryException(401, 'AUTH_REQUIRED')),
      'Se requiere volver a verificar el acceso en línea.',
    );
    expect(
      friendlyError(const SyncQueryException(403, 'AUTH_CONTEXT_FORBIDDEN')),
      'El sindicato no autorizó esta cuenta o este dispositivo.',
    );
  });

  testWidgets('el aviso que ve la persona no lleva el texto técnico', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showError(
                context,
                const SyncQueryException(404, 'OPERATION_NOT_FOUND'),
              ),
              child: const Text('Consultar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Consultar'));
    await tester.pump();
    expect(
      find.textContaining('No se pudo consultar al sindicato'),
      findsOneWidget,
    );
    expect(find.textContaining('SyncQueryException'), findsNothing);
    expect(find.textContaining('OPERATION_NOT_FOUND'), findsNothing);
  });
}
