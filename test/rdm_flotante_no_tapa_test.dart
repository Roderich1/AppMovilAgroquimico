// «+ Registrar» no tapa ninguna fila (revisión del autor, 2026-11-12).
//
// Antes el contenido pasaba por detrás del botón flotante y sólo se reservaba
// su alto al final de la página: con la lista arriba, el botón tapaba la
// existencia de la tarjeta que quedaba debajo (Almacén, captura a 900 dp).
// Ahora la vista desplazable termina por encima del botón. Se comprueba sobre
// la app real con la base sintética de la sesión B (nombres largos, L y KG,
// vencimientos) en Almacén y Actividad, las dos listas que conservan el
// botón, en estrecho y ancho, vertical y horizontal, con letra al 100, 130 y
// 200 %, en TODAS las posiciones del desplazamiento.
import 'package:agroquimicos/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';
import 'support_rdm/b_seed.dart';

typedef _View = ({String name, Size size});

const _views = <_View>[
  (name: 'estrecho vertical 360×800', size: Size(360, 800)),
  (name: 'Pixel 8 vertical 412×915', size: Size(412, 915)),
  (name: 'Pixel 8 horizontal 915×412', size: Size(915, 412)),
  (name: 'ancho 1280×800', size: Size(1280, 800)),
];

const _scales = [1.0, 1.3, 2.0];

void main() {
  sqfliteFfiInit();

  for (final view in _views) {
    for (final scale in _scales) {
      final label = '${view.name}, letra ${(scale * 100).round()} %';

      testWidgets('Almacén: ninguna tarjeta pasa por detrás de «+ Registrar»; '
          'la última se ve entera y se toca ($label)', (tester) async {
        tester.view.physicalSize = view.size * 2;
        tester.view.devicePixelRatio = 2;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final s = await activatedHousehold(tester, 'rdm-flotante-almacen');
        await tester.runAsync(() => seedSessionB(s.household));
        final c = await pumpModeApp(tester, s.database);
        c.read(routerProvider).go('/inventario');
        await settle(tester);

        final fab = find.byKey(const Key('shell-registrar'));
        expect(fab, findsOneWidget);
        final fabRect = tester.getRect(fab);
        // La lista de la página (en ancho, el riel también se desplaza).
        final scrollable = find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first;
        final viewport = tester.getRect(scrollable);
        // La vista desplazable termina por encima del botón: nada de la lista
        // puede quedar debajo de él, en ninguna posición.
        expect(
          viewport.bottom,
          lessThanOrEqualTo(fabRect.top),
          reason: 'vista $viewport, botón $fabRect',
        );
        expect(viewport.bottom, lessThanOrEqualTo(view.size.height));

        final cards = find.byWidgetPredicate(
          (w) =>
              w is InkWell &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(
                'inventory-product-',
              ),
        );
        expect(cards, findsNWidgets(4), reason: 'cuatro productos sembrados');

        final position = tester.state<ScrollableState>(scrollable).position;
        // Recorre el desplazamiento de punta a punta: en cada parada, ninguna
        // tarjeta visible se cruza con el botón.
        for (var offset = 0.0; ; offset += 60) {
          position.jumpTo(offset.clamp(0, position.maxScrollExtent));
          await tester.pump();
          for (final element in cards.evaluate()) {
            final rect = tester.getRect(find.byWidget(element.widget));
            final visible = rect.intersect(viewport);
            if (visible.isEmpty) continue;
            expect(
              visible.overlaps(fabRect),
              isFalse,
              reason: 'en $offset la tarjeta $rect se cruza con $fabRect',
            );
          }
          if (offset >= position.maxScrollExtent) break;
        }

        // Al final, la última tarjeta está entera en la vista y el toque en
        // su existencia llega a la tarjeta (no al botón).
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        final last = cards.evaluate().last.widget;
        final lastRect = tester.getRect(find.byWidget(last));
        expect(
          viewport.contains(lastRect.topLeft) &&
              viewport.contains(lastRect.bottomRight - const Offset(1, 1)),
          isTrue,
          reason: 'última tarjeta $lastRect dentro de $viewport',
        );
        final figure = Offset(lastRect.right - 24, lastRect.center.dy);
        final hits = tester.hitTestOnBinding(figure);
        final lastBox = tester.renderObject(find.byWidget(last));
        expect(
          hits.path.any((entry) => entry.target == lastBox),
          isTrue,
          reason: 'el toque en la existencia llega a la tarjeta',
        );
        expect(
          hits.path.any((entry) => entry.target == tester.renderObject(fab)),
          isFalse,
        );

        // En ancho (lista ≥ 640 × escala de la letra) las tarjetas van de dos en dos; en estrecho,
        // una por fila. Ningún nombre ni cantidad se pierde.
        position.jumpTo(0);
        await tester.pump();
        final rects = [
          for (final element in cards.evaluate())
            tester.getRect(find.byWidget(element.widget)),
        ];
        final twoColumns = rects[0].top == rects[1].top;
        // Márgenes de 16 a cada lado de la lista.
        expect(
          twoColumns,
          viewport.width - 32 >= 640 * scale,
          reason: 'columnas por ancho ${viewport.width}: $rects',
        );
        // El Pixel 8 en horizontal con letra normal es el caso ancho real:
        // ahí la existencia tiene que quedar cerca del nombre.
        if (view.size == const Size(915, 412) && scale == 1.0) {
          expect(twoColumns, isTrue, reason: 'Pixel 8 horizontal: $rects');
        }
        if (view.size.width < 600) {
          expect(twoColumns, isFalse, reason: 'teléfono vertical: $rects');
        }
        for (final text in const [
          'Fungicida sistémico de amplio espectro Carbendazim 50 SC',
          'Urea granulada',
        ]) {
          expect(find.text(text), findsOneWidget);
        }
        expect(find.textContaining('KG'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Actividad: la lista termina por encima de «+ Registrar» '
          '($label)', (tester) async {
        tester.view.physicalSize = view.size * 2;
        tester.view.devicePixelRatio = 2;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final s = await activatedHousehold(tester, 'rdm-flotante-actividad');
        await tester.runAsync(() => seedSessionB(s.household));
        final c = await pumpModeApp(tester, s.database);
        c.read(routerProvider).go('/operaciones');
        await settle(tester);

        final fabRect = tester.getRect(
          find.byKey(const Key('shell-registrar')),
        );
        final viewport = tester.getRect(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          viewport.bottom,
          lessThanOrEqualTo(fabRect.top),
          reason: 'vista $viewport, botón $fabRect',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
