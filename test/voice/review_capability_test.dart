import 'package:agroquimicos/voice/port/review_capability.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cuándo se usa la segunda pasada en un aparato (#166).
///
/// Los mínimos de memoria son un criterio de prudencia, no una medición: lo
/// que habilita la revisión en un teléfono son los umbrales de #12 medidos en
/// él. Estas pruebas fijan la regla, no su acierto en un teléfono concreto.
void main() {
  const policy = ReviewCapabilityPolicy();
  const gib = 1024 * 1024 * 1024;

  ReviewCapability eval({
    String? model = 'whisper-small-q5_1',
    bool runnable = true,
    String? variant,
    int? total,
    bool? lowRam,
    String? failure,
  }) => policy.evaluate(
    ReviewDeviceFacts(
      modelName: model,
      runnable: runnable,
      variant: variant,
      totalMemBytes: total,
      lowRamDevice: lowRam,
      loadFailure: failure,
    ),
  );

  group('variante del modelo', () {
    test('se toma del manifiesto o del nombre de la carpeta', () {
      expect(
        ReviewModelVariant.from(name: 'whisper-small-q5_1'),
        ReviewModelVariant.small,
      );
      expect(
        ReviewModelVariant.from(name: 'whisper-base-q5_1'),
        ReviewModelVariant.base,
      );
      expect(
        ReviewModelVariant.from(variant: 'small', name: 'whisper-base-q5_1'),
        ReviewModelVariant.small,
      );
      expect(
        ReviewModelVariant.from(name: 'whisper-medium-q5_0'),
        ReviewModelVariant.unknown,
      );
    });
  });

  group('sin segunda pasada: sólo Vosk, con su motivo', () {
    test('el APK no trae modelo de revisión (`none`)', () {
      final c = eval(model: null, runnable: false, total: 8 * gib);
      expect(c.allowed, isFalse);
      expect(c.reason, 'review-not-built');
    });

    test('la librería nativa no cargó', () {
      final c = eval(runnable: false, total: 8 * gib);
      expect(c.allowed, isFalse);
      expect(c.reason, 'review-native-lib');
    });

    test('el modelo ya falló al cargarse en este proceso', () {
      final c = eval(total: 8 * gib, failure: 'review-OutOfMemoryError');
      expect(c.allowed, isFalse);
      expect(c.reason, 'review-load-failed:review-OutOfMemoryError');
    });

    test('el sistema se declara de poca memoria, aunque informe mucha', () {
      final c = eval(total: 8 * gib, lowRam: true);
      expect(c.allowed, isFalse);
      expect(c.reason, 'review-low-ram-device');
    });

    test('small en un teléfono de 3 GB', () {
      final c = eval(total: 3 * gib - 200 * 1024 * 1024, lowRam: false);
      expect(c.allowed, isFalse);
      expect(c.reason, 'review-ram-below:3400');
    });

    test('small sin saber la memoria total: no se intenta', () {
      final c = eval(total: null);
      expect(c.allowed, isFalse);
      expect(c.reason, 'review-ram-unknown');
    });

    test('un modelo desconocido exige el mínimo más alto', () {
      final c = eval(model: 'whisper-medium-q5_0', total: 3 * gib);
      expect(c.allowed, isFalse);
      expect(c.reason, 'review-ram-below:3400');
    });

    test('base en un teléfono de 1,5 GB', () {
      final c = eval(model: 'whisper-base-q5_1', total: 1536 * 1024 * 1024);
      expect(c.allowed, isFalse);
      expect(c.reason, 'review-ram-below:1700');
    });
  });

  group('con segunda pasada', () {
    test('small en un teléfono «de 4 GB» (totalMem ≈ 3,6 GiB)', () {
      final c = eval(total: 3686 * 1024 * 1024, lowRam: false);
      expect(c.allowed, isTrue);
      expect(c.reason, 'review-ok');
    });

    test('base sin dato de memoria: como los APK anteriores', () {
      final c = eval(model: 'whisper-base-q5_1', total: null);
      expect(c.allowed, isTrue);
    });

    test('los mínimos se pueden cambiar sin tocar la regla', () {
      const strict = ReviewCapabilityPolicy(
        minTotalMemBytes: {
          ReviewModelVariant.base: 4 * gib,
          ReviewModelVariant.small: 8 * gib,
          ReviewModelVariant.unknown: 8 * gib,
        },
      );
      final facts = ReviewDeviceFacts(
        modelName: 'whisper-small-q5_1',
        runnable: true,
        totalMemBytes: 6 * gib,
      );
      expect(strict.evaluate(facts).reason, 'review-ram-below:8192');
      expect(policy.evaluate(facts).allowed, isTrue);
    });
  });

  test('lee los hechos de `describe` y tolera un APK que no los informa', () {
    final full = ReviewDeviceFacts.fromDescribe({
      'reviewModel': 'whisper-small-q5_1',
      'reviewVariant': 'small',
      'reviewAvailable': true,
      'totalMemBytes': 6 * gib,
      'lowRamDevice': false,
      'reviewDetail': null,
    });
    expect(full.totalMemBytes, 6 * gib);
    expect(full.lowRamDevice, isFalse);
    expect(policy.evaluate(full).allowed, isTrue);

    final old = ReviewDeviceFacts.fromDescribe({
      'reviewModel': 'whisper-base-q5_1',
      'reviewAvailable': true,
    });
    expect(old.totalMemBytes, isNull);
    expect(policy.evaluate(old).allowed, isTrue);
  });
}
