import 'package:agroquimicos/voice/port/speech_transcription_port.dart';
import 'package:agroquimicos/voice/session/voice_locale_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// La lista de fallback de idiomas es parte del contrato de `EVO-009`.
///
/// `ADR-002` la exige documentada y probada: `es-BO` no existe como idioma de
/// reconocimiento, `es-ES` puede no estar instalado y en el teléfono medido sólo
/// funcionó `es-US`. Fijar ese resultado en el código convertiría una medición
/// puntual en una regla para todos los aparatos, así que lo que se prueba aquí
/// es que hay **recorrido**, no un valor fijo.
void main() {
  const policy = VoiceLocalePolicy();

  TranscriptionAvailability availability({
    bool known = true,
    List<String> installed = const [],
    List<String> supported = const [],
  }) => TranscriptionAvailability(
    recognizerAvailable: true,
    onDeviceApiReports: false,
    localeSupportKnown: known,
    installedLocales: installed,
    supportedLocales: supported,
  );

  group('la lista exacta', () {
    test('es la documentada, en ese orden', () {
      expect(VoiceLocalePolicy.candidates, const [
        'es-BO',
        'es-419',
        'es-PE',
        'es-AR',
        'es-CL',
        'es-CO',
        'es-MX',
        'es-US',
        'es-ES',
        'es',
      ]);
    });

    test('el locale pedido por el producto es es-BO', () {
      expect(VoiceLocalePolicy.requested, 'es-BO');
      expect(VoiceLocalePolicy.candidates.first, VoiceLocalePolicy.requested);
    });

    test('sólo contiene español: nunca se escucha en otro idioma', () {
      for (final locale in VoiceLocalePolicy.candidates) {
        expect(
          locale == 'es' || locale.startsWith('es-'),
          isTrue,
          reason: '$locale no es español',
        );
      }
    });

    test('no hay candidatos repetidos', () {
      expect(
        VoiceLocalePolicy.candidates.toSet(),
        hasLength(VoiceLocalePolicy.candidates.length),
      );
    });
  });

  group('cuando el sistema no deja consultar los idiomas (API 31)', () {
    test('se intenta la lista completa, en orden', () {
      expect(
        policy.attemptOrder(availability(known: false)),
        VoiceLocalePolicy.candidates,
      );
    });

    test('empieza por es-BO aunque ADR-002 lo midiera fallando', () {
      expect(policy.attemptOrder(availability(known: false)).first, 'es-BO');
    });
  });

  group('cuando sí se pueden consultar (API 33+)', () {
    test('los instalados van primero, respetando el orden de preferencia', () {
      final order = policy.attemptOrder(
        availability(installed: ['en-US', 'es-MX', 'es-ES']),
      );
      expect(order.first, 'es-MX');
      expect(order.indexOf('es-MX'), lessThan(order.indexOf('es-ES')));
    });

    test('los soportados pero no instalados van después de los instalados', () {
      final order = policy.attemptOrder(
        availability(installed: ['es-ES'], supported: ['es-419']),
      );
      expect(order.first, 'es-ES');
      expect(order[1], 'es-419');
    });

    test('acepta el guion bajo y las mayúsculas de Android', () {
      final order = policy.attemptOrder(availability(installed: ['ES_us']));
      expect(order.first, 'es-US');
    });

    test(
      'ningún español declarado: se intenta igualmente la lista completa',
      () {
        // Negarse a intentar porque lo dijo una API sería confiar en ella justo
        // donde `ADR-002` demostró que no se puede.
        expect(
          policy.attemptOrder(availability(installed: ['en-US', 'pt-BR'])),
          VoiceLocalePolicy.candidates,
        );
      },
    );

    test('nunca se pierde un candidato al reordenar', () {
      final order = policy.attemptOrder(
        availability(installed: ['es-US'], supported: ['es-ES']),
      );
      expect(order.toSet(), VoiceLocalePolicy.candidates.toSet());
      expect(order, hasLength(VoiceLocalePolicy.candidates.length));
    });
  });

  group('cuándo se pasa al siguiente idioma', () {
    test('sólo un idioma no disponible avanza el recorrido', () {
      expect(
        policy.advancesLocale(TranscriptionErrorCode.localeUnavailable),
        isTrue,
      );
    });

    test('un permiso denegado no se arregla cambiando de idioma', () {
      for (final code in const [
        TranscriptionErrorCode.permissionDenied,
        TranscriptionErrorCode.permissionPermanentlyDenied,
        TranscriptionErrorCode.recognizerUnavailable,
        TranscriptionErrorCode.networkRequired,
        TranscriptionErrorCode.clientError,
        TranscriptionErrorCode.busy,
        TranscriptionErrorCode.serverError,
        TranscriptionErrorCode.engineFailure,
      ]) {
        expect(policy.advancesLocale(code), isFalse, reason: code.name);
      }
    });
  });
}
