/// Si este teléfono puede ejecutar la segunda pasada local (#166).
///
/// La segunda pasada (whisper.cpp) es **condicional**: sólo con el modo de
/// revisión activo y en un teléfono que la admita. Si no la admite, el
/// recorrido es sólo Vosk, sin error, y la disponibilidad dice por qué.
///
/// ## Qué se comprueba, y qué no
///
/// El lado nativo informa hechos del aparato, sin interpretarlos:
///
/// * si el APK trae un modelo de revisión y la librería nativa cargó;
/// * la memoria total (`ActivityManager.MemoryInfo.totalMem`) y si el sistema
///   se declara de poca memoria (`ActivityManager.isLowRamDevice`);
/// * si el modelo ya falló al cargarse en este proceso.
///
/// La decisión vive aquí, en Dart, para poder probarla sin teléfono.
///
/// **Los mínimos de memoria total son un criterio de prudencia, no una
/// medición.** Dicen qué teléfonos ni siquiera se intentan; no prueban que la
/// revisión funcione bien en los demás. Lo que habilita la segunda pasada en
/// un teléfono concreto son los umbrales de #12 medidos en ese teléfono
/// (final p50 ≤ 2 500 ms y p95 ≤ 5 000 ms, RTF p95 ≤ 0,50, memoria pico total
/// ≤ 1,2 GB, 0 caídas en 30 sesiones), hoy `NOT_MEASURED`.
library;

/// Variante del modelo de revisión empaquetado al compilar
/// (`tool/voice_local/fetch_voice_models.sh base|small|none`).
enum ReviewModelVariant {
  base,
  small,

  /// Un nombre que no se reconoce: se trata con el mínimo más exigente.
  unknown;

  /// La variante a partir de lo que dice el lado nativo: el campo explícito
  /// del manifiesto si lo hay, y si no el nombre de la carpeta del modelo
  /// (`whisper-base-q5_1`, `whisper-small-q5_1`).
  static ReviewModelVariant from({String? variant, String? name}) {
    final source = (variant ?? name ?? '').toLowerCase();
    if (RegExp(r'(^|[-_])small([-_]|$)').hasMatch(source)) return small;
    if (RegExp(r'(^|[-_])base([-_]|$)').hasMatch(source)) return base;
    return unknown;
  }
}

/// Hechos del aparato que informa `describe` del lado nativo.
final class ReviewDeviceFacts {
  const ReviewDeviceFacts({
    required this.modelName,
    required this.runnable,
    this.variant,
    this.totalMemBytes,
    this.lowRamDevice,
    this.loadFailure,
  });

  /// Lee el mapa de `describe`. Los campos que falten (un APK anterior) quedan
  /// como desconocidos.
  factory ReviewDeviceFacts.fromDescribe(Map<String, Object?> map) =>
      ReviewDeviceFacts(
        modelName: map['reviewModel'] as String?,
        runnable: map['reviewAvailable'] as bool? ?? false,
        variant: map['reviewVariant'] as String?,
        totalMemBytes: (map['totalMemBytes'] as num?)?.toInt(),
        lowRamDevice: map['lowRamDevice'] as bool?,
        loadFailure: map['reviewDetail'] as String?,
      );

  /// Nombre del modelo del manifiesto, o `null` si el APK no trae ninguno.
  final String? modelName;

  /// Hay modelo **y** la librería nativa cargó.
  final bool runnable;

  /// Variante declarada en el manifiesto, si la declara.
  final String? variant;

  /// Memoria total del aparato, o `null` si no se pudo leer.
  final int? totalMemBytes;

  /// `ActivityManager.isLowRamDevice()`, o `null` si no se pudo leer.
  final bool? lowRamDevice;

  /// Código del fallo de carga del modelo o de la librería en este proceso
  /// (`review-model-load`, `review-OutOfMemoryError`…), o `null`.
  final String? loadFailure;
}

/// Resultado de la comprobación. [allowed] es `false` ⇒ sólo Vosk.
final class ReviewCapability {
  const ReviewCapability._(this.allowed, this.reason);

  /// No hay datos todavía (no se consultó la disponibilidad).
  static const unknown = ReviewCapability._(false, 'review-unknown');

  final bool allowed;

  /// Código sin contenido dictado: `review-ok`, `review-not-built`,
  /// `review-native-lib`, `review-low-ram-device`,
  /// `review-ram-below:<MiB>`, `review-ram-unknown`,
  /// `review-load-failed:<código>`.
  final String reason;

  @override
  String toString() => 'ReviewCapability($allowed, $reason)';
}

/// Decide si se usa la segunda pasada en este aparato.
final class ReviewCapabilityPolicy {
  const ReviewCapabilityPolicy({
    this.minTotalMemBytes = const {
      ReviewModelVariant.base: defaultMinBase,
      ReviewModelVariant.small: defaultMinSmall,
      ReviewModelVariant.unknown: defaultMinSmall,
    },
    this.requireKnownMemoryFor = const {
      ReviewModelVariant.small,
      ReviewModelVariant.unknown,
    },
  });

  /// Un teléfono «de 2 GB» informa en `totalMem` algo menos de 2 GiB (el
  /// núcleo se reserva una parte). Base pesa ~60 MB y en el PC ocupó
  /// ~230 MB con su contexto: se admite desde esa clase.
  static const defaultMinBase = 1700 * 1024 * 1024;

  /// Small pesa ~190 MB y en el PC ocupó ~430 MB con su contexto, además de
  /// Vosk: se exige la clase «de 4 GB» (`totalMem` ≈ 3,5–3,8 GiB).
  static const defaultMinSmall = 3400 * 1024 * 1024;

  /// Mínimo de memoria total por variante.
  final Map<ReviewModelVariant, int> minTotalMemBytes;

  /// Variantes que no se intentan si no se conoce la memoria total. Base no
  /// lo exige para no cambiar el comportamiento de los APK anteriores, que no
  /// la informan.
  final Set<ReviewModelVariant> requireKnownMemoryFor;

  ReviewCapability evaluate(ReviewDeviceFacts facts) {
    final name = facts.modelName;
    if (name == null || name.isEmpty) {
      return const ReviewCapability._(false, 'review-not-built');
    }
    if (!facts.runnable) {
      return ReviewCapability._(
        false,
        facts.loadFailure == null
            ? 'review-native-lib'
            : 'review-load-failed:${facts.loadFailure}',
      );
    }
    if (facts.loadFailure != null) {
      // Ya se intentó cargar y falló (sin memoria, archivo dañado): no se
      // vuelve a intentar en este proceso.
      return ReviewCapability._(
        false,
        'review-load-failed:${facts.loadFailure}',
      );
    }
    if (facts.lowRamDevice == true) {
      return const ReviewCapability._(false, 'review-low-ram-device');
    }
    final variant = ReviewModelVariant.from(variant: facts.variant, name: name);
    final total = facts.totalMemBytes;
    if (total == null || total <= 0) {
      return requireKnownMemoryFor.contains(variant)
          ? const ReviewCapability._(false, 'review-ram-unknown')
          : const ReviewCapability._(true, 'review-ok');
    }
    final minimum = minTotalMemBytes[variant] ?? defaultMinSmall;
    if (total < minimum) {
      return ReviewCapability._(
        false,
        'review-ram-below:${minimum ~/ (1024 * 1024)}',
      );
    }
    return const ReviewCapability._(true, 'review-ok');
  }
}
