// F08-ADR-003: formato cifrado del respaldo. Todo con claves efímeras
// generadas en la prueba; ninguna se imprime.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:agroquimicos/data/backup_encryption.dart';
import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart' show Mac, SecretKeyData;
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _hex(String hex) {
  final clean = hex.replaceAll(RegExp(r'[\s:]'), '');
  return [
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ];
}

void main() {
  late Directory dir;
  const encryption = BackupEncryption();
  const limit = 64 * 1024 * 1024;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('f08_enc_test_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<File> plainFile(int size, {int seed = 7}) async {
    final random = Random(seed);
    final file = File('${dir.path}/plain.agrobackup');
    await file.writeAsBytes(
      Uint8List.fromList(List<int>.generate(size, (_) => random.nextInt(256))),
    );
    return file;
  }

  Future<String> sha(File file) async =>
      '${await hashes.sha256.bind(file.openRead()).first}';

  group('primitivas de la biblioteca fijada (vectores de los RFC)', () {
    test('ChaCha20-Poly1305: RFC 8439 §2.8.2', () async {
      const cipher = DartChacha20.poly1305Aead();
      final box = await cipher.encrypt(
        "Ladies and Gentlemen of the class of '99: If I could offer you only "
                'one tip for the future, sunscreen would be it.'
            .codeUnits,
        secretKey: SecretKeyData(List<int>.generate(32, (i) => 0x80 + i)),
        nonce: _hex('07000000 40414243 44454647'),
        aad: _hex('50515253 c0c1c2c3 c4c5c6c7'),
      );
      expect(
        box.cipherText.sublist(0, 16),
        _hex('d31a8d34648e60db7b86afbc53ef7ec2'),
      );
      expect(box.mac.bytes, _hex('1ae10b594f09e26a7e902ecbd0600691'));
    });

    test('HKDF-SHA256: RFC 5869 A.1', () async {
      final okm =
          await DartHkdf(
            hmac: DartHmac(const DartSha256()),
            outputLength: 42,
          ).deriveKey(
            secretKey: SecretKeyData(List<int>.filled(22, 0x0b)),
            nonce: List<int>.generate(13, (i) => i),
            info: List<int>.generate(10, (i) => 0xf0 + i),
          );
      expect(
        okm.bytes,
        _hex(
          '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
          '34007208d5b887185865',
        ),
      );
    });

    test('la etiqueta se compara en tiempo constante (Mac.==)', () {
      expect(Mac(const [1, 2, 3]) == Mac(const [1, 2, 3]), isTrue);
      expect(Mac(const [1, 2, 3]) == Mac(const [1, 2, 4]), isFalse);
    });
  });

  group('clave de recuperación', () {
    test('se presenta en 14 grupos de 4 y se vuelve a leer igual', () {
      final key = BackupRecoveryKey.generate();
      final text = key.displayText;
      expect(text.split('-'), hasLength(14));
      expect(text.split('-').every((g) => g.length == 4), isTrue);
      expect(BackupRecoveryKey.parse(text).sameAs(key), isTrue);
      // Escrita a mano: minúsculas, espacios y sin guiones.
      final handwritten = text.toLowerCase().replaceAll('-', ' ');
      expect(BackupRecoveryKey.parse(handwritten).sameAs(key), isTrue);
    });

    test('O/0 e I/L/1 se tratan como el mismo carácter', () {
      final key = BackupRecoveryKey.generate(Random(3));
      final text = key.displayText.replaceAll('0', 'O').replaceAll('1', 'l');
      expect(BackupRecoveryKey.parse(text).sameAs(key), isTrue);
    });

    test('un carácter cambiado se detecta como error de escritura', () {
      final key = BackupRecoveryKey.generate(Random(4));
      final chars = key.displayText.replaceAll('-', '').split('');
      chars[10] = chars[10] == 'A' ? 'B' : 'A';
      expect(
        () => BackupRecoveryKey.parse(chars.join()),
        throwsA(
          isA<RecoveryKeyFormatException>().having(
            (e) => e.problem,
            'problem',
            RecoveryKeyProblem.checksum,
          ),
        ),
      );
    });

    test('longitud o caracteres inválidos se rechazan', () {
      for (final bad in ['', 'ABCD-EFGH', '${'U' * 56}']) {
        expect(
          () => BackupRecoveryKey.parse(bad),
          throwsA(isA<RecoveryKeyFormatException>()),
          reason: bad,
        );
      }
    });

    test('toString nunca muestra el secreto', () {
      final key = BackupRecoveryKey.generate();
      expect('$key', 'BackupRecoveryKey(redacted)');
      expect('$key', isNot(contains(key.displayText.substring(0, 4))));
    });

    test(
      'el identificador es estable, distinto entre claves y no es la clave',
      () async {
        final a = BackupRecoveryKey.generate(Random(1));
        final b = BackupRecoveryKey.generate(Random(2));
        expect(await a.keyId(), await a.keyId());
        expect(await a.keyId(), isNot(await b.keyId()));
        expect(await a.keyId(), hasLength(16));
        expect(a.storedBytes.sublist(0, 16), isNot(await a.keyId()));
      },
    );
  });

  group('formato 2: ida y vuelta', () {
    for (final size in [0, 1, 65535, 65536, 300001]) {
      test('$size bytes', () async {
        final key = BackupRecoveryKey.generate();
        final plain = await plainFile(size);
        final envelope = File('${dir.path}/c.agroenc');
        await encryption.encryptFile(plain, envelope, key);
        expect(
          await envelope.length(),
          BackupEnvelopeHeader.length + size + BackupEnvelopeHeader.tagLength,
        );
        expect(await BackupEncryption.isEnvelope(envelope), isTrue);

        final out = File('${dir.path}/out.agrobackup');
        final result = await encryption.decryptFile(
          envelope,
          out,
          keyFor: (_) async => key,
          maxPlaintextBytes: limit,
        );
        expect(result, isNotNull);
        expect(result!.sha256, await sha(plain));
        expect(await sha(out), await sha(plain));
        expect(File('${out.path}.part').existsSync(), isFalse);
      });
    }

    test(
      'dos cifrados del mismo archivo difieren (sal y nonce nuevos)',
      () async {
        final key = BackupRecoveryKey.generate();
        final plain = await plainFile(1000);
        final a = File('${dir.path}/a.agroenc');
        final b = File('${dir.path}/b.agroenc');
        await encryption.encryptFile(plain, a, key);
        await encryption.encryptFile(plain, b, key);
        expect(await sha(a), isNot(await sha(b)));
      },
    );

    test('el texto legible no aparece en el cifrado', () async {
      final key = BackupRecoveryKey.generate();
      final marker = 'MARCADOR-SINTETICO-F08-${'x' * 40}'.codeUnits;
      final plain = File('${dir.path}/plain.agrobackup');
      await plain.writeAsBytes([...marker, ...marker]);
      final envelope = File('${dir.path}/c.agroenc');
      await encryption.encryptFile(plain, envelope, key);
      final bytes = await envelope.readAsBytes();
      expect(String.fromCharCodes(bytes), isNot(contains('MARCADOR')));
    });
  });

  group('formato 2: rechazos sin escribir nada', () {
    late BackupRecoveryKey key;
    late File envelope;
    late File out;

    setUp(() async {
      key = BackupRecoveryKey.generate();
      envelope = File('${dir.path}/c.agroenc');
      out = File('${dir.path}/out.agrobackup');
      await encryption.encryptFile(await plainFile(200000), envelope, key);
    });

    Future<void> expectRejected(
      BackupEnvelopeProblem problem, {
      BackupRecoveryKey? withKey,
    }) async {
      await expectLater(
        encryption.decryptFile(
          envelope,
          out,
          keyFor: (_) async => withKey ?? key,
          maxPlaintextBytes: limit,
        ),
        throwsA(
          isA<BackupEnvelopeException>().having(
            (e) => e.problem,
            'problem',
            problem,
          ),
        ),
      );
      expect(out.existsSync(), isFalse);
      expect(File('${out.path}.part').existsSync(), isFalse);
    }

    Future<void> mutate(void Function(Uint8List bytes) change) async {
      final bytes = await envelope.readAsBytes();
      change(bytes);
      await envelope.writeAsBytes(bytes, flush: true);
    }

    test('clave incorrecta: se detecta por el identificador', () async {
      await expectRejected(
        BackupEnvelopeProblem.wrongKey,
        withKey: BackupRecoveryKey.generate(),
      );
    });

    test('sin la clave en el llavero: no descifra ni escribe', () async {
      final result = await encryption.decryptFile(
        envelope,
        out,
        keyFor: (_) async => null,
        maxPlaintextBytes: limit,
      );
      expect(result, isNull);
      expect(out.existsSync(), isFalse);
    });

    test('un bit alterado en el ciphertext', () async {
      await mutate((b) => b[BackupEnvelopeHeader.length + 1234] ^= 0x01);
      await expectRejected(BackupEnvelopeProblem.authenticationFailed);
    });

    test('el último bloque alterado', () async {
      await mutate(
        (b) => b[b.length - BackupEnvelopeHeader.tagLength - 1] ^= 0x80,
      );
      await expectRejected(BackupEnvelopeProblem.authenticationFailed);
    });

    test('la etiqueta alterada', () async {
      await mutate((b) => b[b.length - 1] ^= 0x01);
      await expectRejected(BackupEnvelopeProblem.authenticationFailed);
    });

    test('sal o nonce alterados (AAD)', () async {
      await mutate((b) => b[30] ^= 0x01);
      await expectRejected(BackupEnvelopeProblem.authenticationFailed);
      await encryption.encryptFile(await plainFile(5000), envelope, key);
      await mutate((b) => b[65] ^= 0x01);
      await expectRejected(BackupEnvelopeProblem.authenticationFailed);
    });

    test('identificador de clave alterado: otra clave', () async {
      await mutate((b) => b[12] ^= 0x01);
      await expectRejected(BackupEnvelopeProblem.wrongKey);
    });

    test('versión, algoritmo o indicadores desconocidos', () async {
      for (final offset in [9, 10, 11]) {
        await encryption.encryptFile(await plainFile(100), envelope, key);
        await mutate((b) => b[offset] ^= 0x04);
        await expectRejected(BackupEnvelopeProblem.unsupported);
      }
    });

    test('magic alterado', () async {
      await mutate((b) => b[0] = 0x50);
      await expectRejected(BackupEnvelopeProblem.malformed);
    });

    test('truncado: en el ciphertext y sin la etiqueta', () async {
      final bytes = await envelope.readAsBytes();
      for (final cut in [bytes.length - 1, bytes.length - 16, 100000, 81]) {
        await envelope.writeAsBytes(bytes.sublist(0, cut), flush: true);
        await expectRejected(BackupEnvelopeProblem.malformed);
      }
    });

    test(
      'truncado con la longitud declarada ajustada: falla la etiqueta',
      () async {
        final bytes = await envelope.readAsBytes();
        final shorter = bytes.length - 1000;
        final truncated = Uint8List.fromList([
          ...bytes.sublist(0, shorter - 16),
          ...bytes.sublist(bytes.length - 16),
        ]);
        ByteData.sublistView(truncated).setUint64(
          72,
          shorter -
              BackupEnvelopeHeader.length -
              BackupEnvelopeHeader.tagLength,
        );
        await envelope.writeAsBytes(truncated, flush: true);
        await expectRejected(BackupEnvelopeProblem.authenticationFailed);
      },
    );

    test('bytes añadidos al final', () async {
      await envelope.writeAsBytes([0, 1, 2], mode: FileMode.append);
      await expectRejected(BackupEnvelopeProblem.malformed);
    });

    test(
      'longitud declarada por encima del límite, antes de descifrar',
      () async {
        await expectLater(
          encryption.decryptFile(
            envelope,
            out,
            keyFor: (_) async => fail('no debe pedir la clave'),
            maxPlaintextBytes: 1000,
          ),
          throwsA(
            isA<BackupEnvelopeException>().having(
              (e) => e.problem,
              'problem',
              BackupEnvelopeProblem.tooLarge,
            ),
          ),
        );
        expect(out.existsSync(), isFalse);
      },
    );

    test('longitud declarada enorme (bit alto): malformado', () async {
      await mutate((b) => b[72] = 0xff);
      await expectRejected(BackupEnvelopeProblem.malformed);
    });

    test('un destino previo no se pierde si falla la verificación', () async {
      await out.writeAsString('anterior');
      await mutate((b) => b[BackupEnvelopeHeader.length] ^= 0x01);
      await expectLater(
        encryption.decryptFile(
          envelope,
          out,
          keyFor: (_) async => key,
          maxPlaintextBytes: limit,
        ),
        throwsA(isA<BackupEnvelopeException>()),
      );
      expect(await out.readAsString(), 'anterior');
      expect(File('${out.path}.part').existsSync(), isFalse);
    });
  });
}
