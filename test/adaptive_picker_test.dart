import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('picker con 50 items busca y mantiene panel limitado', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveEntityPicker<int>(
            label: 'Producto',
            items: List.generate(50, (i) => i),
            value: selected,
            labelOf: (i) => 'Producto $i',
            secondaryOf: (i) => 'Disponible',
            onChanged: (v) => selected = v,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Seleccionar'));
    await tester.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('50/50'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar'),
      'Producto 49',
    );
    await tester.pump();
    expect(find.text('1/50'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Producto 49'));
    await tester.pumpAndSettle();
    expect(selected, 49);
    expect(tester.takeException(), isNull);
  });
  testWidgets('picker autoselecciona opción inequívoca', (tester) async {
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveEntityPicker<int>(
            label: 'Persona',
            items: const [7],
            value: selected,
            labelOf: (i) => '$i',
            onChanged: (v) => selected = v,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(selected, 7);
  });
}
