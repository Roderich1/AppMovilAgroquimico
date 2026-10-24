// F08-ADR-003 §3.8: nada de Agrocuentas entra en el respaldo automático de
// Android ni en la transferencia entre dispositivos. Se leen las reglas del
// repositorio; las empaquetadas en el APK se comprueban con aapt2 (evidencia).
import 'dart:io';

import 'package:agroquimicos/services/auth/secure_session_store.dart';
import 'package:agroquimicos/services/backup/backup_keyring.dart';
import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res/xml';

/// Los dominios que usa la app (inventario del ADR) y lo que guarda en cada uno.
const _privateState = <(String, String)>[
  ('database', 'agroquimicos_v2.db'),
  ('database', 'agroquimicos_v2.db-journal'),
  ('database', 'agroquimicos_v2.db-wal'),
  ('database', 'agroquimicos_v2.db-shm'),
  ('database', 'previo/registro.json'),
  ('database', 'agroquimicos_v2.db.descifrado'),
  ('root', 'app_flutter/invoices/factura.jpg'),
  ('root', 'app_flutter/agrocuentas.log'),
  ('root', 'app_flutter/respaldo.agrobackup'),
  ('file', 'remote_backups/privado/copia.descifrado'),
  ('sharedpref', 'AgrocuentasSessionPointer.xml'),
  ('external', 'Download/respaldo.agrobackup'),
  ('external', 'Download/informe.pdf'),
];

/// Los tres archivos de cada almacén seguro de flutter_secure_storage 11.2.0.
List<String> _secureStorageFiles(String namespace) => [
  '$namespace.xml',
  'FlutterSecureKeyStorage:$namespace.xml',
  'FlutterSecureStorageConfiguration:$namespace.xml',
];

class _Rule {
  _Rule(this.tag, this.domain, this.path);
  final String tag;
  final String domain;
  final String path;
}

String _withoutComments(String xml) =>
    xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

List<_Rule> _rules(String xml) => [
  for (final m in RegExp(
    r'<(include|exclude)\s+domain="([^"]+)"\s+path="([^"]+)"\s*/>',
  ).allMatches(xml))
    _Rule(m[1]!, m[2]!, m[3]!),
];

/// Una exclusión cubre el archivo si es su dominio entero o una ruta suya.
bool _excluded(List<_Rule> rules, String domain, String path) => rules.any(
  (r) =>
      r.tag == 'exclude' &&
      r.domain == domain &&
      (r.path == '.' || path == r.path || path.startsWith('${r.path}/')),
);

void _expectNothingLeaves(String section, List<_Rule> rules) {
  expect(
    rules.where((r) => r.tag == 'include'),
    isEmpty,
    reason: '$section: una inclusión limitaría el respaldo a lo incluido',
  );
  for (final domain in ['database', 'root', 'file', 'sharedpref', 'external']) {
    expect(
      rules.any(
        (r) => r.tag == 'exclude' && r.domain == domain && r.path == '.',
      ),
      isTrue,
      reason: '$section: falta excluir el dominio $domain entero',
    );
  }
  final namespaces = [
    SecureSessionStore.androidNamespace,
    'agrocuentas_owner_credential_v1',
    SecureStorageBackupKeyVault.androidNamespace,
  ];
  for (final (domain, path) in [
    ..._privateState,
    for (final ns in namespaces)
      for (final file in _secureStorageFiles(ns)) ('sharedpref', file),
  ]) {
    expect(
      _excluded(rules, domain, path),
      isTrue,
      reason: '$section: $domain/$path saldría del teléfono',
    );
  }
}

void main() {
  test(
    'Android 11 y anteriores: la base, las fotos, las copias, los temporales, '
    'las exportaciones y los almacenes seguros quedan fuera del respaldo',
    () {
      final xml = File('$_res/backup_rules.xml').readAsStringSync();
      expect(xml, contains('<full-backup-content>'));
      _expectNothingLeaves(
        'full-backup-content',
        _rules(_withoutComments(xml)),
      );
    },
  );

  test('Android 12+: lo mismo en la copia en la nube y en la transferencia '
      'entre dispositivos', () {
    final xml = _withoutComments(
      File('$_res/data_extraction_rules.xml').readAsStringSync(),
    );
    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = RegExp(
        '<$section>(.*?)</$section>',
        dotAll: true,
      ).firstMatch(xml);
      expect(body, isNotNull, reason: 'falta <$section>');
      _expectNothingLeaves(section, _rules(body![1]!));
    }
    // Ninguna regla fuera de las dos secciones.
    final outside = xml.replaceAll(
      RegExp(r'<(cloud-backup|device-transfer)>.*?</\1>', dotAll: true),
      '',
    );
    expect(_rules(outside), isEmpty);
  });

  test('el manifiesto usa las dos reglas y no depende de allowBackup', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });

  test('las comprobaciones detectan una regla que deja salir algo', () {
    final partial = _rules(
      '<exclude domain="database" path="previo" />'
      '<exclude domain="sharedpref" path="${SecureStorageBackupKeyVault.androidNamespace}.xml" />',
    );
    expect(_excluded(partial, 'database', 'previo/registro.json'), isTrue);
    expect(_excluded(partial, 'database', 'agroquimicos_v2.db-wal'), isFalse);
    expect(
      _excluded(partial, 'sharedpref', 'agrocuentas_secure_session_v1.xml'),
      isFalse,
    );
    expect(_excluded(partial, 'root', 'app_flutter/invoices/a.jpg'), isFalse);
  });
}
