import 'package:agroquimicos/voice_draft/form/voice_form_merge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reglas de incorporación de un dictado al formulario único (F09). Valores
/// canónicos sintéticos: productos por id, cantidades en unidades base,
/// precios en centavos.
void main() {
  const herbicida = 11, fungicida = 12, proveedor = 7, otroProveedor = 8;

  ProposedValue v(Object value, [String? display]) =>
      ProposedValue(value, display: display ?? '$value');

  FormSnapshot form({
    Map<String, Object?> header = const {},
    List<LineSnapshot> lines = const [],
  }) => FormSnapshot(header: header, lines: lines);

  LineSnapshot line(int id, {int? product, int? quantity, int? price}) =>
      LineSnapshot(id, {
        'product': product,
        'quantity': quantity,
        'price': price,
      });

  MergePlan plan(
    FormSnapshot before,
    VoiceProposal proposal, {
    FormSnapshot? now,
  }) => planVoiceMerge(
    before: before,
    now: now ?? before,
    proposal: proposal,
    nextLineId: 100,
  );

  group('campos', () {
    test('vacío + valor inequívoco → se completa', () {
      final p = plan(
        form(header: {'supplier': null}),
        VoiceProposal(header: {'supplier': v(proveedor, 'Agro DEMO')}),
      );
      expect(p.changes.single.slot, const SlotRef.header('supplier'));
      expect(p.changes.single.after, proveedor);
      expect(p.choices, isEmpty);
    });

    test('mismo valor → se conserva sin duplicar', () {
      final p = plan(
        form(header: {'supplier': proveedor}),
        VoiceProposal(header: {'supplier': v(proveedor)}),
      );
      expect(p.changesNothing, isTrue);
      expect(p.unchanged, 1);
    });

    test('otro valor → se pide elegir; no se sobrescribe', () {
      final p = plan(
        form(header: {'supplier': proveedor}),
        VoiceProposal(header: {'supplier': v(otroProveedor, 'Otro')}),
      );
      expect(p.changes, isEmpty);
      expect(p.choices.single.current, proveedor);
      expect(p.choices.single.proposed, otroProveedor);
    });

    test('ambiguo → revisión; el campo no cambia', () {
      final p = plan(
        form(lines: [line(1, product: herbicida)]),
        const VoiceProposal(
          lines: [
            ProposedLine({
              'price': ProposedValue(
                5000,
                display: '50 Bs',
                review: VoiceReview(
                  '¿Por litro o total?',
                  options: [
                    ReviewOption('Por L', 5000),
                    ReviewOption('Total', 2500),
                  ],
                ),
              ),
            }),
          ],
        ),
      );
      expect(p.changes, isEmpty);
      expect(p.reviews.single.slot, const SlotRef.line(1, 'price'));
      expect(p.reviews.single.review.options, hasLength(2));
    });

    test('lo no dicho se conserva', () {
      final p = plan(
        form(
          header: {'supplier': proveedor},
          lines: [line(1, product: herbicida, quantity: 2000)],
        ),
        const VoiceProposal(),
      );
      expect(p.changesNothing, isTrue);
    });

    test('editado durante el procesamiento → gana la persona', () {
      final before = form(header: {'supplier': null});
      final now = form(header: {'supplier': otroProveedor});
      final p = plan(
        before,
        VoiceProposal(header: {'supplier': v(proveedor)}),
        now: now,
      );
      expect(p.changes, isEmpty);
      expect(p.choices, isEmpty);
      expect(p.keptEdited, [const SlotRef.header('supplier')]);
    });
  });

  group('líneas', () {
    test('la línea dictada usa la línea inicial vacía', () {
      final p = plan(
        form(lines: [line(1)]),
        VoiceProposal(
          lines: [
            ProposedLine({
              'product': v(herbicida),
              'quantity': v(2000),
              'price': v(5000),
            }),
          ],
        ),
      );
      expect(p.newLines, isEmpty);
      expect(p.changes.map((c) => c.slot.line).toSet(), {1});
      expect(p.changes, hasLength(3));
    });

    test('mixto: producto elegido a mano y cantidad y precio dictados', () {
      final p = plan(
        form(lines: [line(1, product: herbicida)]),
        VoiceProposal(
          lines: [
            ProposedLine({'quantity': v(2000), 'price': v(5000)}),
          ],
        ),
      );
      expect(p.newLines, isEmpty);
      expect(p.changes.map((c) => c.slot).toSet(), {
        const SlotRef.line(1, 'quantity'),
        const SlotRef.line(1, 'price'),
      });
    });

    test('con líneas llenas, la línea dictada se añade y se muestra nueva', () {
      final p = plan(
        form(lines: [line(1, product: herbicida, quantity: 1000, price: 100)]),
        VoiceProposal(
          lines: [
            ProposedLine({'product': v(fungicida), 'quantity': v(3000)}),
          ],
        ),
      );
      expect(p.newLines.single.line, 100);
      expect(p.newLines.single.values, {
        'product': fungicida,
        'quantity': 3000,
      });
      expect(p.newLines.single.repeatOf, isNull);
    });

    test('producto repetido: no se suma ni se fusiona; queda por revisar', () {
      final p = plan(
        form(lines: [line(1, product: herbicida, quantity: 1000, price: 100)]),
        VoiceProposal(
          lines: [
            ProposedLine({
              'product': v(herbicida, 'Herbicida'),
              'quantity': v(2000),
            }),
          ],
        ),
      );
      // La línea 1 no cambia.
      expect(p.changes, isEmpty);
      final added = p.newLines.single;
      expect(added.repeatOf, 1);
      expect(added.values.containsKey('product'), isFalse);
      expect(added.values['quantity'], 2000);
      expect(p.reviews.single.slot, const SlotRef.line(100, 'product'));
    });

    test(
      'dos líneas dictadas con el mismo producto: la segunda por revisar',
      () {
        final p = plan(
          form(lines: [line(1)]),
          VoiceProposal(
            lines: [
              ProposedLine({'product': v(herbicida), 'quantity': v(1000)}),
              ProposedLine({'product': v(herbicida), 'quantity': v(2000)}),
            ],
          ),
        );
        expect(p.changes.where((c) => c.slot.field == 'product'), hasLength(1));
        expect(p.newLines.single.repeatOf, 1);
      },
    );

    test('negación u otra intención (propuesta vacía) → ningún cambio', () {
      final p = plan(
        form(lines: [line(1)]),
        const VoiceProposal(notices: ['Eso parece una aplicación.']),
      );
      expect(p.changesNothing, isTrue);
      expect(p.notices, ['Eso parece una aplicación.']);
    });

    test('línea creada a mano durante el turno no se usa como vacía', () {
      final before = form(
        lines: [line(1, product: herbicida, quantity: 1, price: 1)],
      );
      final now = form(
        lines: [
          line(1, product: herbicida, quantity: 1, price: 1),
          line(2),
        ],
      );
      final p = plan(
        before,
        VoiceProposal(
          lines: [
            ProposedLine({'product': v(fungicida)}),
          ],
        ),
        now: now,
      );
      expect(p.newLines.single.values, {'product': fungicida});
    });
  });

  group('deshacer', () {
    test(
      'restaura lo que sigue como lo dejó la voz y quita líneas intactas',
      () {
        const record = DictationRecord(
          changes: [
            FieldChange(SlotRef.header('supplier'), null, proveedor, ''),
            FieldChange(SlotRef.line(1, 'quantity'), null, 2000, ''),
          ],
          createdLines: {
            100: {'product': fungicida, 'quantity': 3000},
          },
        );
        final now = form(
          header: {'supplier': proveedor},
          lines: [
            line(1, product: herbicida, quantity: 2000),
            const LineSnapshot(100, {
              'product': fungicida,
              'quantity': 3000,
              'price': null,
            }),
          ],
        );
        final u = planVoiceUndo(record, now);
        expect(u.restore.map((c) => c.slot).toSet(), {
          const SlotRef.header('supplier'),
          const SlotRef.line(1, 'quantity'),
        });
        expect(u.restore.every((c) => c.after == null), isTrue);
        expect(u.removeLines, [100]);
        expect(u.keptEdited, isEmpty);
      },
    );

    test('no pierde ediciones posteriores', () {
      const record = DictationRecord(
        changes: [FieldChange(SlotRef.header('supplier'), null, proveedor, '')],
        createdLines: {
          100: {'product': fungicida, 'quantity': 3000},
        },
      );
      final now = form(
        header: {'supplier': otroProveedor}, // cambiado a mano después
        lines: [
          const LineSnapshot(100, {
            'product': fungicida,
            'quantity': 4000,
            'price': null,
          }),
        ],
      );
      final u = planVoiceUndo(record, now);
      expect(u.restore, isEmpty);
      expect(u.removeLines, isEmpty);
      expect(u.keptEdited, hasLength(2));
    });
  });
}
