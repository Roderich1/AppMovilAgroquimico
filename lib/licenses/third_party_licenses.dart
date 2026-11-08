import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Avisos de licencia de lo que la APK con voz local distribuye y que el aviso
/// de Flutter (`NOTICES`, paquetes Dart y motor) no cubre: los binarios de
/// Vosk, JNA, whisper.cpp y ggml, y los modelos de voz.
///
/// Los textos están en `assets/licenses/`, copiados byte a byte de su fuente
/// oficial; `assets/licenses/README.md` dice de dónde sale cada uno (URL,
/// versión o commit y SHA-256). Aquí no se escribe ningún texto legal: sólo
/// una nota por componente que dice qué archivo de la APK cubre y, en JNA,
/// qué licencia de las dos se aplica.
@immutable
class ThirdPartyNotice {
  const ThirdPartyNotice({
    required this.package,
    required this.note,
    required this.assets,
  });

  /// Nombre con el que aparece en la página de licencias.
  final String package;

  /// Nota de Agrocuentas (no es texto legal).
  final String note;

  /// Textos oficiales, en el orden en que se muestran.
  final List<String> assets;
}

const thirdPartyNotices = <ThirdPartyNotice>[
  ThirdPartyNotice(
    package: 'Vosk (vosk-android 0.3.75)',
    note:
        'Motor de reconocimiento de voz principal: libvosk.so y sus clases '
        'Java, del paquete com.alphacephei:vosk-android:0.3.75 (Alpha Cephei). '
        'Licencia Apache 2.0.',
    assets: ['assets/licenses/vosk/COPYING'],
  ),
  ThirdPartyNotice(
    package: 'JNA (Java Native Access 5.18.1)',
    note:
        'libjnidispatch.so y sus clases Java, del paquete '
        'net.java.dev.jna:jna:5.18.1, que Vosk usa. JNA se ofrece bajo dos '
        'licencias a elección: Apache 2.0 o LGPL 2.1 o posterior. Agrocuentas '
        'la usa bajo Apache 2.0. libjnidispatch.so incluye libffi, cuyo aviso '
        'va al final.',
    assets: [
      'assets/licenses/jna/LICENSE',
      'assets/licenses/jna/AL2.0',
      'assets/licenses/jna/libffi/LICENSE',
    ],
  ),
  ThirdPartyNotice(
    package: 'whisper.cpp',
    note:
        'Segunda pasada del reconocimiento: libagro_whisper.so, compilada desde '
        'whisper.cpp, commit 52a939a2a762224e255d366c1182b2af4dd1a032, con un '
        'puente JNI de Agrocuentas derivado de su ejemplo para Android. '
        'Licencia MIT.',
    assets: ['assets/licenses/whisper_cpp/LICENSE'],
  ),
  ThirdPartyNotice(
    package: 'ggml',
    note:
        'libggml.so, libggml-base.so y libggml-cpu.so, compiladas desde la '
        'copia de ggml incluida en whisper.cpp, commit 52a939a (sincronizada '
        'con ggml, commit e91ded1). Licencia MIT.',
    assets: ['assets/licenses/ggml/LICENSE'],
  ),
  ThirdPartyNotice(
    package: 'Modelo de voz Vosk vosk-model-small-es-0.42',
    note:
        'Modelo de español de Alpha Cephei, dentro de la APK. Su archivo no '
        'trae texto de licencia: se muestra su README tal como viene, y el '
        'texto de la licencia Apache 2.0, que es la que le asigna la lista '
        'oficial de modelos de Vosk (https://alphacephei.com/vosk/models).',
    assets: [
      'assets/licenses/vosk_model_small_es_0_42/README',
      'assets/licenses/vosk_model_small_es_0_42/LICENSE-2.0.txt',
    ],
  ),
  ThirdPartyNotice(
    package: 'Modelo de voz Whisper (OpenAI), formato ggml',
    note:
        'Pesos del modelo Whisper de OpenAI, licencia MIT, convertidos a '
        'formato ggml y publicados en https://huggingface.co/ggerganov/'
        'whisper.cpp (licencia MIT). La APK lleva la variante base '
        '(ggml-base-q5_1.bin); una compilación con la opción small lleva '
        'ggml-small-q5_1.bin, con la misma licencia.',
    assets: ['assets/licenses/whisper_model/LICENSE'],
  ),
];

bool _registered = false;

/// Sólo para pruebas: permite registrar otra vez tras `LicenseRegistry.reset`.
@visibleForTesting
void resetThirdPartyLicensesForTest() => _registered = false;

/// Añade los avisos de [thirdPartyNotices] al `LicenseRegistry` de Flutter.
/// Se puede llamar varias veces: sólo registra la primera.
void registerThirdPartyLicenses({AssetBundle? bundle}) {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() => _entries(bundle ?? rootBundle));
}

Stream<LicenseEntry> _entries(AssetBundle bundle) async* {
  for (final notice in thirdPartyNotices) {
    yield LicenseEntryWithLineBreaks([notice.package], notice.note);
    for (final asset in notice.assets) {
      yield LicenseEntryWithLineBreaks([
        notice.package,
      ], await bundle.loadString(asset, cache: false));
    }
  }
}

/// Abre la página de licencias de Flutter con los avisos de terceros.
void showAgroLicenses(BuildContext context) {
  registerThirdPartyLicenses();
  showLicensePage(context: context, applicationName: 'Agrocuentas');
}
