// F06 (MOB #33): el constructor del total de consumo es una función pura.
import 'package:agroquimicos/domain/numeric_input.dart' show maxBaseQuantity;
import 'package:agroquimicos/domain/sync/consumption_projection.dart';
import 'package:agroquimicos/domain/sync/sync_types.dart';
import 'package:flutter_test/flutter_test.dart';

const _owner = 1;
const _family = 2;
const _campaign = 10;

AppliedLine _line(
  int application,
  int product,
  int quantity, {
  int person = _owner,
  int campaign = _campaign,
  String status = 'CONFIRMED',
  bool reversed = false,
}) => AppliedLine(
  applicationId: application,
  personId: person,
  campaignId: campaign,
  productId: product,
  status: status,
  reversed: reversed,
  quantityBase: quantity,
);

BoundRef _ref(String ref, {bool valid = true, BaseUnit? unit}) => BoundRef(
  ref: ref,
  localName: 'local $ref',
  centralName: 'central $ref',
  valid: valid,
  baseUnit: unit,
);

final _campaigns = {_campaign: _ref('c')};
final _products = {
  100: _ref('l1', unit: BaseUnit.ml),
  101: _ref('k1', unit: BaseUnit.g),
  102: _ref('l2', unit: BaseUnit.ml),
};

ConsumptionProjection _build(
  List<AppliedLine> lines, {
  Map<int, BoundRef>? campaigns,
  Map<int, BoundRef>? products,
}) => buildConsumptionProjection(
  ownerPersonId: _owner,
  lines: lines,
  campaigns: campaigns ?? _campaigns,
  products: products ?? _products,
);

Map<int, int> _totals(ConsumptionProjection projection) => {
  for (final cell in projection.cells) cell.productId: cell.quantityBase,
};

void main() {
  test(
    'una aplicación con tres productos aporta exactamente a tres totales',
    () {
      final projection = _build([
        _line(1, 100, 2500),
        _line(1, 101, 1500),
        _line(1, 102, 700),
        _line(2, 100, 1000),
      ]);
      expect(_totals(projection), {100: 3500, 101: 1500, 102: 700});
      expect(
        projection.cells
            .firstWhere((cell) => cell.productId == 100)
            .applications,
        2,
      );
      expect(projection.cells.map((cell) => cell.baseUnit), [
        BaseUnit.ml,
        BaseUnit.g,
        BaseUnit.ml,
      ]);
    },
  );

  test('una reversión resta toda la aplicación de cada total', () {
    final projection = _build([
      _line(1, 100, 2500, status: 'REVERSED', reversed: true),
      _line(1, 101, 1500, status: 'REVERSED', reversed: true),
      _line(2, 100, 1000),
    ]);
    expect(_totals(projection), {100: 1000});
    expect(projection.excludedLines[ConsumptionExclusion.reversed], 2);
  });

  test('en compartido, el consumo de un familiar nunca se proyecta', () {
    final projection = _build([
      _line(1, 100, 2500),
      _line(2, 100, 9000, person: _family),
    ]);
    expect(_totals(projection), {100: 2500});
    expect(projection.excludedLines[ConsumptionExclusion.notOwner], 1);
  });

  test('campaña o producto sin vínculo vigente: se excluye y se avisa', () {
    final projection = _build(
      [_line(1, 100, 10), _line(1, 103, 20), _line(2, 101, 30)],
      products: {
        100: _ref('l1', unit: BaseUnit.ml),
        101: _ref('k1', valid: false, unit: BaseUnit.g),
      },
    );
    expect(_totals(projection), {100: 10});
    expect(
      {
        for (final pair in projection.excludedPairs)
          pair.productId: pair.reason,
      },
      {
        103: ConsumptionExclusion.productNotBound,
        101: ConsumptionExclusion.productBindingInvalid,
      },
    );
    final noCampaign = _build([_line(1, 100, 10)], campaigns: {});
    expect(noCampaign.cells, isEmpty);
    expect(
      noCampaign.excludedPairs.single.reason,
      ConsumptionExclusion.campaignNotBound,
    );
    final invalidCampaign = _build(
      [_line(1, 100, 10)],
      campaigns: {_campaign: _ref('c', valid: false)},
    );
    expect(
      invalidCampaign.excludedPairs.single.reason,
      ConsumptionExclusion.campaignBindingInvalid,
    );
  });

  test('sumas grandes sin pérdida; por encima de int64 no se publica', () {
    final exact = _build([
      _line(1, 100, maxBaseQuantity - 1),
      _line(2, 100, 1),
    ]);
    expect(_totals(exact), {100: maxBaseQuantity});
    final over = _build([_line(1, 100, maxBaseQuantity), _line(2, 100, 1)]);
    expect(over.cells, isEmpty);
    expect(over.excludedPairs.single.reason, ConsumptionExclusion.overflow);
  });

  test('sin líneas propias vigentes no hay total (ausencia, no cero)', () {
    expect(_build([]).cells, isEmpty);
    expect(
      _build([_line(1, 100, 10, status: 'REVERSED', reversed: true)]).cells,
      isEmpty,
    );
  });
}
