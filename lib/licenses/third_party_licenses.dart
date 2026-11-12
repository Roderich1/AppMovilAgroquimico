import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Avisos de licencia de lo que la APK con voz local distribuye y que el aviso
/// de Flutter (`NOTICES`, paquetes Dart y motor) no cubre: los binarios de
/// Vosk, JNA, whisper.cpp y ggml, y los modelos de voz. Además, el código Java
/// que el plugin `integration_test` (dependencia de desarrollo) mete en las
/// compilaciones que no son release, como la *profile* de «AC F09».
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
    this.onlyOutsideRelease = false,
  });

  /// Nombre con el que aparece en la página de licencias.
  final String package;

  /// Nota de Agrocuentas (no es texto legal).
  final String note;

  /// Textos oficiales, en el orden en que se muestran.
  final List<String> assets;

  /// Sólo viaja en compilaciones debug y profile: el plugin de Gradle de
  /// Flutter no añade las dependencias de desarrollo a release.
  final bool onlyOutsideRelease;
}

const _apache2 = 'assets/licenses/apache-2.0/LICENSE-2.0.txt';
const _viaIntegrationTest = '(vía integration_test, compilación profile)';
const _itNote =
    'No es de Agrocuentas ni de la voz: lo trae el plugin integration_test, '
    'una dependencia de desarrollo que Flutter incluye en las compilaciones '
    'debug y profile, no en release. ';

const thirdPartyNotices = <ThirdPartyNotice>[
  ThirdPartyNotice(
    package: 'Vosk (vosk-android 0.3.75)',
    note:
        'Motor de reconocimiento de voz principal: libvosk.so y sus clases '
        'Java, del paquete com.alphacephei:vosk-android:0.3.75 (Alpha Cephei). '
        'Licencia Apache 2.0. libvosk.so incluye Kaldi, OpenFST, OpenBLAS, '
        'CLAPACK y libf2c, con sus avisos a continuación.',
    assets: ['assets/licenses/vosk/COPYING'],
  ),
  ThirdPartyNotice(
    package: 'Kaldi (incluido en Vosk)',
    note:
        'Reconocedor de voz compilado dentro de libvosk.so, desde la rama '
        'vosk-android de https://github.com/alphacep/kaldi. Licencia Apache '
        '2.0.',
    assets: ['assets/licenses/vosk/kaldi/COPYING'],
  ),
  ThirdPartyNotice(
    package: 'OpenFST (incluido en Vosk)',
    note:
        'Biblioteca de transductores de estados finitos compilada dentro de '
        'libvosk.so (OpenFST 1.8.0, copia de Alpha Cephei en '
        'https://github.com/alphacep/openfst). Licencia Apache 2.0.',
    assets: ['assets/licenses/vosk/openfst/COPYING'],
  ),
  ThirdPartyNotice(
    package: 'OpenBLAS 0.3.20 (incluido en Vosk)',
    note:
        'Rutinas de álgebra lineal (sólo CBLAS) compiladas dentro de '
        'libvosk.so, desde la etiqueta v0.3.20 de '
        'https://github.com/OpenMathLib/OpenBLAS. Se muestran su licencia y el '
        'aviso de GotoBLAS2, del que deriva.',
    assets: [
      'assets/licenses/vosk/openblas/LICENSE',
      'assets/licenses/vosk/openblas/GotoBLAS_00License.txt',
    ],
  ),
  ThirdPartyNotice(
    package: 'CLAPACK 3.2.1 y libf2c (incluidos en Vosk)',
    note:
        'LAPACK traducido a C y su biblioteca de soporte libf2c, compilados '
        'dentro de libvosk.so desde la rama v3.2.1 de '
        'https://github.com/alphacep/clapack. Se muestran el aviso de CLAPACK '
        'y el de libf2c.',
    assets: [
      'assets/licenses/vosk/clapack/COPYING',
      'assets/licenses/vosk/clapack/libf2c/Notice',
    ],
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
    assets: ['assets/licenses/vosk_model_small_es_0_42/README', _apache2],
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
  // Rediseño móvil (2026-11-12): tipografías de la interfaz, dentro de la APK
  // en assets/fonts/. Son instancias estáticas (pesos fijos) de las fuentes
  // variables de google/fonts; el procedimiento está en assets/licenses/
  // README.md. Ninguna declara «Reserved Font Name».
  ThirdPartyNotice(
    package: 'DM Sans (tipografía)',
    note:
        'Tipografía del texto de la interfaz: DMSans-400, -500 y -700.ttf, '
        'instancias estáticas de la fuente variable de google/fonts. SIL Open '
        'Font License 1.1.',
    assets: ['assets/licenses/fonts/dm_sans/OFL.txt'],
  ),
  ThirdPartyNotice(
    package: 'Bricolage Grotesque (tipografía)',
    note:
        'Tipografía de títulos y cifras: BricolageGrotesque-700 y -800.ttf, '
        'instancias estáticas de la fuente variable de google/fonts. SIL Open '
        'Font License 1.1.',
    assets: ['assets/licenses/fonts/bricolage_grotesque/OFL.txt'],
  ),
  ThirdPartyNotice(
    package: 'integration_test, plugin de Flutter 3.47.2 $_viaIntegrationTest',
    note:
        '${_itNote}Su parte Android (dev.flutter.plugins.integration_test) es '
        'del SDK de Flutter, licencia BSD.',
    assets: ['assets/licenses/integration_test/flutter/LICENSE'],
    onlyOutsideRelease: true,
  ),
  ThirdPartyNotice(
    package: 'JUnit 4.12 $_viaIntegrationTest',
    note: '${_itNote}junit:junit:4.12. Eclipse Public License 1.0.',
    assets: [
      'assets/licenses/integration_test/junit/LICENSE-junit.txt',
      'assets/licenses/integration_test/junit/NOTICE.txt',
    ],
    onlyOutsideRelease: true,
  ),
  ThirdPartyNotice(
    package: 'Hamcrest 1.3 $_viaIntegrationTest',
    note:
        '${_itNote}org.hamcrest:hamcrest-core, hamcrest-library y '
        'hamcrest-integration 1.3. Licencia BSD.',
    assets: ['assets/licenses/integration_test/hamcrest/LICENSE.txt'],
    onlyOutsideRelease: true,
  ),
  ThirdPartyNotice(
    package: 'AndroidX Test y Espresso $_viaIntegrationTest',
    note:
        '${_itNote}androidx.test:runner 1.3.0, monitor 1.3.0 y rules 1.2.0; '
        'androidx.test.espresso:espresso-core y espresso-idling-resource '
        '3.3.0. Licencia Apache 2.0.',
    assets: [_apache2],
    onlyOutsideRelease: true,
  ),
  ThirdPartyNotice(
    package: 'Guava 28.1-android y failureaccess 1.0.1 $_viaIntegrationTest',
    note:
        '${_itNote}com.google.guava:guava:28.1-android y failureaccess:1.0.1. '
        'Licencia Apache 2.0.',
    assets: [_apache2],
    onlyOutsideRelease: true,
  ),
  ThirdPartyNotice(
    package: 'J2ObjC Annotations 1.3 $_viaIntegrationTest',
    note:
        '${_itNote}com.google.j2objc:j2objc-annotations:1.3. Licencia Apache '
        '2.0.',
    assets: [_apache2],
    onlyOutsideRelease: true,
  ),
  ThirdPartyNotice(
    package: 'JavaWriter 2.1.1 $_viaIntegrationTest',
    note:
        '${_itNote}com.squareup:javawriter:2.1.1 (Square). Licencia Apache 2.0.',
    assets: [_apache2],
    onlyOutsideRelease: true,
  ),
  ThirdPartyNotice(
    package: 'javax.inject 1 $_viaIntegrationTest',
    note:
        '${_itNote}javax.inject:javax.inject:1. Su repositorio no trae archivo '
        'de licencia: se muestra la cabecera de sus fuentes y el texto de la '
        'licencia Apache 2.0.',
    assets: [
      'assets/licenses/integration_test/javax_inject/Inject.java-cabecera.txt',
      _apache2,
    ],
    onlyOutsideRelease: true,
  ),
  ThirdPartyNotice(
    package: 'Checker Framework compat-qual 2.5.5 $_viaIntegrationTest',
    note:
        '${_itNote}org.checkerframework:checker-compat-qual:2.5.5: sólo '
        'anotaciones, que según este archivo están bajo la licencia MIT.',
    assets: ['assets/licenses/integration_test/checker_framework/LICENSE.txt'],
    onlyOutsideRelease: true,
  ),
  ThirdPartyNotice(
    package: 'Animal Sniffer Annotations 1.18 $_viaIntegrationTest',
    note:
        '${_itNote}org.codehaus.mojo:animal-sniffer-annotations:1.18. Su '
        'repositorio no trae archivo de licencia: se muestra la cabecera MIT '
        'de su fuente.',
    assets: [
      'assets/licenses/integration_test/animal_sniffer/'
          'IgnoreJRERequirement.java-cabecera.txt',
    ],
    onlyOutsideRelease: true,
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
    if (notice.onlyOutsideRelease && kReleaseMode) continue;
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
