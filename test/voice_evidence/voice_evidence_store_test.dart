// F09-VOZ-13 (MOB #167): evidencia de dictado con consentimiento.
// Consentimiento explícito y revocable, campos propuestos, correcciones y
// confirmados por separado, borrado y ningún audio. Todos los textos son
// SINTÉTICOS: ninguno procede de un dictado real.
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/app.dart' show databaseProvider;
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/voice_draft/catalog/voice_catalog.dart';
import 'package:agroquimicos/voice_draft/core/draft_field.dart';
import 'package:agroquimicos/voice_draft/core/voice_draft_controller.dart';
import 'package:agroquimicos/voice_draft/plan/voice_plan_draft.dart';
import 'package:agroquimicos/voice_draft/text/units.dart';
import 'package:agroquimicos/voice_evidence/draft_snapshot.dart';
import 'package:agroquimicos/voice_evidence/voice_evidence.dart';
import 'package:agroquimicos/voice_evidence/voice_evidence_providers.dart';
import 'package:agroquimicos/voice_evidence/voice_evidence_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/f04_mode_fixtures.dart';
import 'evidence_fixtures.dart';

VoiceEvidenceEntry confirmedEntry({
  DateTime? startedAt,
  String? sheetRef = 'FICHA-C1',
}) {
  final trace = VoiceEvidenceTrace(clock: () => startedAt ?? clockAt(30));
  trace.voiceApplied(voiceProposal(), transcript: marker);
  return trace.finish(
    finalDraft: corrected(voiceProposal()),
    outcome: VoiceEvidenceOutcome.confirmed,
    sheetRef: sheetRef,
    engine: 'local',
    model: 'modelo-sintetico',
    appCommit: '0000000',
    firstPartialMs: 640,
    finalMs: 2900,
  );
}

void main() {
  sqfliteFfiInit();

  late AppDatabase database;
  late VoiceEvidenceStore store;
  var minute = 0;

  setUp(() {
    minute = 0;
    database = openDb(inMemoryDatabasePath);
    store = VoiceEvidenceStore(database, clock: () => clockAt(minute));
  });

  Future<List<Map<String, Object?>>> rows() async =>
      (await database.database).query('voice_evidence', orderBy: 'id');

  group('sin consentimiento no se guarda nada', () {
    test('una base nueva no tiene consentimiento ni evidencia', () async {
      expect(await store.consent(), isNull);
      expect(await rows(), isEmpty);
    });

    test(
      'confirmar, descartar o fallar sin consentimiento no deja filas',
      () async {
        expect(
          await store.record(confirmedEntry()),
          VoiceEvidenceRecordResult.noConsent,
        );
        for (final outcome in [
          VoiceEvidenceOutcome.discarded,
          VoiceEvidenceOutcome.failed,
        ]) {
          final trace = VoiceEvidenceTrace()
            ..voiceApplied(voiceProposal(), transcript: marker);
          expect(
            await store.record(
              trace.finish(finalDraft: voiceProposal(), outcome: outcome),
            ),
            VoiceEvidenceRecordResult.noConsent,
          );
        }
        expect(await rows(), isEmpty);
        expect(await store.readAll(), isEmpty);
      },
    );

    test('el sumidero por defecto es nulo y no toca la base', () async {
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      addTearDown(container.dispose);
      await store.grantConsent(consentTextVersion: consentV1);
      final sink = container.read(voiceEvidenceSinkProvider);
      expect(sink, isA<NullVoiceEvidenceSink>());
      expect(
        await sink.record(confirmedEntry()),
        VoiceEvidenceRecordResult.noConsent,
      );
      expect(await rows(), isEmpty);
    });

    test(
      'con la sobrescritura de evaluación, el sumidero es el almacén',
      () async {
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(database),
            recordVoiceEvidenceOverride,
          ],
        );
        addTearDown(container.dispose);
        final sink = container.read(voiceEvidenceSinkProvider);
        expect(sink, isA<VoiceEvidenceStore>());
        // Sigue sin guardar nada mientras no haya consentimiento.
        expect(
          await sink.record(confirmedEntry()),
          VoiceEvidenceRecordResult.noConsent,
        );
        expect(await rows(), isEmpty);
      },
    );
  });

  group('consentimiento explícito, separado y con fecha', () {
    test('se registra con la versión del texto y la fecha; repetirlo no lo renueva', () async {
      minute = 5;
      final first = await store.grantConsent(consentTextVersion: consentV1);
      expect(first.consentTextVersion, consentV1);
      expect(first.grantedAt, clockAt(5));
      minute = 9;
      final again = await store.grantConsent(consentTextVersion: 'otro');
      expect(again.grantedAt, clockAt(5));
      expect(again.consentTextVersion, consentV1);
    });

    test('no se guarda en app_settings ni depende de otro ajuste', () async {
      final db = await database.database;
      final before = await settings(db);
      await store.grantConsent(consentTextVersion: consentV1);
      expect(await settings(db), before);
      final consentRows = await db.query('voice_evidence_consent');
      expect(consentRows.single['purpose'], voiceEvidencePurpose);
    });

    test('exige identificar el texto aceptado', () async {
      expect(
        () => store.grantConsent(consentTextVersion: '  '),
        throwsArgumentError,
      );
      expect(await store.consent(), isNull);
    });

    test('un dictado empezado antes del consentimiento no se guarda', () async {
      minute = 40;
      await store.grantConsent(consentTextVersion: consentV1);
      expect(
        await store.record(confirmedEntry(startedAt: clockAt(39))),
        VoiceEvidenceRecordResult.consentAfterDictation,
      );
      expect(await rows(), isEmpty);
      expect(
        await store.record(confirmedEntry(startedAt: clockAt(41))),
        VoiceEvidenceRecordResult.stored,
      );
    });
  });

  group(
    'con consentimiento: propuestos, correcciones y confirmados por separado',
    () {
      test(
        'las tres partes quedan en columnas distintas y se leen igual',
        () async {
          await store.grantConsent(consentTextVersion: consentV1);
          minute = 31;
          expect(
            await store.record(confirmedEntry()),
            VoiceEvidenceRecordResult.stored,
          );
          final row = (await rows()).single;
          expect(row['kind'], 'PURCHASE');
          expect(row['outcome'], 'CONFIRMED');
          expect(row['sheet_ref'], 'FICHA-C1');
          expect(jsonDecode(row['transcripts']! as String), [marker]);
          expect(row['engine'], 'local');
          expect(row['model'], 'modelo-sintetico');
          expect(row['app_commit'], '0000000');
          expect(row['first_partial_ms'], 640);
          expect(row['final_ms'], 2900);

          final proposed =
              jsonDecode(row['proposed_fields']! as String) as List;
          final proposedByPath = <Object?, dynamic>{
            for (final f in proposed) (f as Map)['path']: f,
          };
          expect(proposedByPath['line[1].quantity'], {
            'path': 'line[1].quantity',
            'status': 'resolved',
            'origin': 'voice',
            'value': {'thousandths': 1000, 'unit': 'liter'},
          });
          expect(proposedByPath['line[1].currency']['status'], 'missing');
          expect(proposedByPath['supplier']['value'], {
            'id': 7,
            'name': 'Agro Norte',
          });

          final corrections = jsonDecode(row['corrections']! as String) as List;
          expect(
            {for (final c in corrections) (c as Map)['path']: c['kind']},
            {'line[1].quantity': 'CHANGED', 'line[1].currency': 'CHANGED'},
          );
          final quantity = corrections.firstWhere(
            (c) => (c as Map)['path'] == 'line[1].quantity',
          );
          expect(quantity['proposed']['value'], {
            'thousandths': 1000,
            'unit': 'liter',
          });
          expect(quantity['final']['value'], {
            'thousandths': 1500,
            'unit': 'liter',
          });

          final confirmed =
              jsonDecode(row['confirmed_fields']! as String) as List;
          final confirmedByPath = <Object?, dynamic>{
            for (final f in confirmed) (f as Map)['path']: f,
          };
          expect(confirmedByPath['line[1].quantity']['origin'], 'manual');
          expect(confirmedByPath['line[1].currency']['value'], 'bob');
          expect(confirmedByPath['line[1].product']['origin'], 'voice');

          final stored = (await store.readAll()).single;
          expect(stored.kind, VoiceEvidenceKind.purchase);
          expect(stored.outcome, VoiceEvidenceOutcome.confirmed);
          expect(stored.consentGrantedAt, clockAt(0));
          expect(stored.recordedAt, clockAt(31));
          expect(stored.transcripts, [marker]);
          expect(stored.proposed, hasLength(proposed.length));
          expect(stored.corrections, hasLength(2));
          expect(stored.confirmed, hasLength(confirmed.length));
        },
      );

      test('un descarte o un fallo guardan propuestos y correcciones, sin confirmados', () async {
        await store.grantConsent(consentTextVersion: consentV1);
        for (final outcome in [
          VoiceEvidenceOutcome.discarded,
          VoiceEvidenceOutcome.failed,
        ]) {
          final trace = VoiceEvidenceTrace(clock: () => clockAt(1))
            ..voiceApplied(voiceProposal(), transcript: marker);
          expect(
            await store.record(
              trace.finish(
                finalDraft: corrected(voiceProposal()),
                outcome: outcome,
              ),
            ),
            VoiceEvidenceRecordResult.stored,
          );
        }
        final stored = await rows();
        expect(stored.map((r) => r['outcome']), ['DISCARDED', 'FAILED']);
        for (final row in stored) {
          expect(row['confirmed_fields'], isNull);
          expect(jsonDecode(row['corrections']! as String), hasLength(2));
          // Sin datos de tiempo: NOT_MEASURED, nunca cero.
          expect(row['first_partial_ms'], isNull);
          expect(row['final_ms'], isNull);
          expect(row['sheet_ref'], isNull);
        }
      });

      test('una entrada incoherente se rechaza sin escribir', () async {
        await store.grantConsent(consentTextVersion: consentV1);
        final good = confirmedEntry();
        final incoherent = [
          VoiceEvidenceEntry(
            kind: good.kind,
            outcome: VoiceEvidenceOutcome.discarded,
            transcripts: good.transcripts,
            proposed: good.proposed,
            corrections: good.corrections,
            confirmed: good.confirmed,
          ),
          VoiceEvidenceEntry(
            kind: good.kind,
            outcome: VoiceEvidenceOutcome.confirmed,
            transcripts: good.transcripts,
            proposed: good.proposed,
            corrections: good.corrections,
          ),
          confirmedEntry(sheetRef: ' '),
          confirmedEntry(sheetRef: 'x' * 101),
        ];
        for (final entry in incoherent) {
          expect(await store.record(entry), VoiceEvidenceRecordResult.rejected);
        }
        expect(await rows(), isEmpty);
      });
    },
  );

  group('trazas desde el controlador del borrador (sin modificarlo)', () {
    test('voz, corrección manual, voz tardía y confirmación', () async {
      final trace = VoiceEvidenceTrace(clock: () => clockAt(2));
      final controller = VoiceDraftController<VoicePlanDraft, int>(
        initial: const VoicePlanDraft(
          campaign: DraftField.resolved(campaign, origin: FieldOrigin.preset),
        ),
        commit: (_) async => 99,
      );
      addTearDown(controller.dispose);
      const farm = CatalogEntry(id: 5, name: 'Sur', areaM2: 20000);
      trace.dictationStarted();
      controller.applyVoice(
        (d) => (
          d.copyWith(
            farm: const DraftField.resolved(farm, origin: FieldOrigin.voice),
            area: const DraftField.resolved(20000, origin: FieldOrigin.voice),
            lines: const [
              VoicePlanLine(
                key: 1,
                product: DraftField.resolved(
                  glifosato,
                  origin: FieldOrigin.voice,
                ),
                dose: DraftField.resolved(
                  SpokenDose(2000, SpokenUnit.liter),
                  origin: FieldOrigin.voice,
                ),
              ),
            ],
            nextLineKey: 2,
          ),
          const VoicePatchOutcome(applied: 4),
        ),
      );
      trace.voiceApplied(controller.draft, transcript: marker);
      controller.editManually(
        (d) => d.copyWith(
          area: const DraftField.resolved(15000, origin: FieldOrigin.manual),
        ),
      );
      // Un segundo dictado añade otra línea; el área manual se conserva.
      controller.applyVoice((d) {
        final (area, kept) = mergeField(
          d.area,
          const DraftField.resolved(30000, origin: FieldOrigin.voice),
        );
        return (
          d.copyWith(
            area: area,
            lines: [
              ...d.lines,
              const VoicePlanLine(
                key: 2,
                product: DraftField.resolved(
                  CatalogEntry(
                    id: 2,
                    name: 'Mancozeb',
                    unit: CatalogUnit.kilogram,
                  ),
                  origin: FieldOrigin.voice,
                ),
              ),
            ],
            nextLineKey: 3,
          ),
          kept,
        );
      });
      trace.voiceApplied(controller.draft, transcript: '$marker 2');
      controller.updateLinesManually(2);
      expect(await controller.confirm(), 99);

      final entry = trace.finish(
        finalDraft: controller.draft,
        outcome: VoiceEvidenceOutcome.confirmed,
      );
      expect(entry.kind, VoiceEvidenceKind.plan);
      expect(entry.transcripts, [marker, '$marker 2']);
      expect(entry.dictationStartedAt, clockAt(2));
      final proposed = {for (final f in entry.proposed) f.path: f};
      // Lo que propuso la voz para el área (20000), no el valor manual.
      expect(proposed['area']!.value, 20000);
      expect(proposed['line[2].dose']!.status, 'missing');
      expect(
        {for (final c in entry.corrections) c.path: c.kind},
        {
          'area': CorrectionKind.changed,
          'line[2].dose': CorrectionKind.changed,
        },
      );
      final confirmed = {for (final f in entry.confirmed!) f.path: f};
      expect(confirmed['area']!.value, 15000);
      expect(confirmed['line[2].dose']!.value, {
        'thousandthsPerHa': 3000,
        'unit': 'kilogram',
      });
    });

    test('quitar una línea propuesta y añadir otra a mano', () {
      final trace = VoiceEvidenceTrace()..voiceApplied(voiceProposal());
      final finalDraft = voiceProposal()
          .removeLine(1)
          .addEmptyLine()
          .updateLine(
            2,
            (l) => l.copyWith(
              product: const DraftField.resolved(
                glifosato,
                origin: FieldOrigin.manual,
              ),
            ),
          );
      final kinds = {
        for (final c
            in trace
                .finish(
                  finalDraft: finalDraft,
                  outcome: VoiceEvidenceOutcome.discarded,
                )
                .corrections)
          c.path: c.kind,
      };
      expect(kinds['line[1].product'], CorrectionKind.removed);
      expect(kinds['line[1].quantity'], CorrectionKind.removed);
      expect(kinds['line[2].product'], CorrectionKind.added);
      // Los campos vacíos de la línea nueva no son correcciones.
      expect(kinds.containsKey('line[2].quantity'), isFalse);
    });

    test('elegir a mano el mismo valor que propuso la voz es «reafirmado»', () {
      final trace = VoiceEvidenceTrace()..voiceApplied(voiceProposal());
      final finalDraft = voiceProposal().copyWith(
        supplier: const DraftField.resolved(
          agroNorte,
          origin: FieldOrigin.manual,
        ),
      );
      final corrections = trace
          .finish(
            finalDraft: finalDraft,
            outcome: VoiceEvidenceOutcome.discarded,
          )
          .corrections;
      expect(corrections.single.path, 'supplier');
      expect(corrections.single.kind, CorrectionKind.reaffirmed);
    });
  });

  group('borrado', () {
    test(
      'retirar el consentimiento borra todo y no deja el texto en el archivo',
      () async {
        final path = await tempDbPath('retirada');
        final onDisk = openDb(path);
        final diskStore = VoiceEvidenceStore(onDisk);
        await diskStore.grantConsent(consentTextVersion: consentV1);
        for (var i = 0; i < 3; i++) {
          expect(
            await diskStore.record(
              confirmedEntry(startedAt: DateTime.utc(2100)),
            ),
            VoiceEvidenceRecordResult.stored,
          );
        }
        expect(await diskStore.count(), 3);
        expect(await diskStore.revokeConsent(), 3);
        expect(await diskStore.consent(), isNull);
        expect(await diskStore.count(), 0);
        expect(await diskStore.readAll(), isEmpty);
        // Después de retirarlo, nada nuevo se guarda.
        expect(
          await diskStore.record(confirmedEntry()),
          VoiceEvidenceRecordResult.noConsent,
        );
        final db = await onDisk.database;
        expect(
          (await db.rawQuery('PRAGMA secure_delete')).single.values.single,
          0,
          reason: 'secure_delete vuelve a su valor anterior',
        );
        await onDisk.close();
        final bytes = latin1.decode(
          File(path).readAsBytesSync(),
          allowInvalid: true,
        );
        expect(bytes.contains(marker), isFalse);
        expect(bytes.contains('Agro Norte'), isFalse);
      },
    );

    test('borrar la evidencia conserva el consentimiento; también una sola entrada', () async {
      await store.grantConsent(consentTextVersion: consentV1);
      await store.record(confirmedEntry());
      await store.record(confirmedEntry());
      final first = (await store.readAll()).first.id;
      expect(await store.erase(first), isTrue);
      expect(await store.erase(first), isFalse);
      expect(await store.count(), 1);
      expect(await store.eraseAll(), 1);
      expect(await store.consent(), isNotNull);
      expect(
        await store.record(confirmedEntry()),
        VoiceEvidenceRecordResult.stored,
      );
    });
  });

  group('ningún audio', () {
    test('las tablas no tienen columnas binarias ni de audio', () async {
      final db = await database.database;
      for (final table in AppDatabase.voiceEvidenceTables) {
        for (final column in await db.rawQuery('PRAGMA table_info($table)')) {
          final type = '${column['type']}'.toUpperCase();
          final name = '${column['name']}'.toLowerCase();
          expect(type, isNot(contains('BLOB')), reason: '$table.$name');
          expect(name, isNot(contains('audio')), reason: '$table.$name');
          expect(name, isNot(contains('wav')), reason: '$table.$name');
        }
      }
    });

    test(
      'el código de la evidencia no maneja audio ni registra lo dictado',
      () {
        final files = Directory('lib/voice_evidence')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'));
        expect(files, isNotEmpty);
        for (final file in files) {
          final code = file
              .readAsStringSync()
              .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
              .replaceAll(RegExp(r'//[^\r\n]*'), '');
          for (final needle in const [
            'audio',
            'Audio',
            'Uint8List',
            'BLOB',
            'print(',
            'debugPrint',
            'AppLog',
            'app_log',
            'http',
            'sync_outbox',
          ]) {
            expect(
              code.contains(needle),
              isFalse,
              reason: '${file.path} contiene «$needle»',
            );
          }
        }
      },
    );
  });
}

extension on VoiceDraftController<VoicePlanDraft, int> {
  /// La persona completa a mano la dosis de la línea dictada sin dosis.
  void updateLinesManually(int key) => editManually(
    (d) => d.copyWith(
      lines: [
        for (final l in d.lines)
          l.key == key
              ? l.copyWith(
                  dose: const DraftField.resolved(
                    SpokenDose(3000, SpokenUnit.kilogram),
                    origin: FieldOrigin.manual,
                  ),
                )
              : l,
      ],
    ),
  );
}
