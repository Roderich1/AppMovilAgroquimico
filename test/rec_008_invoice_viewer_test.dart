// REC-008 (#44): fotografía de factura.
//
// Criterio 1, en la parte que no depende de la cámara: `storeInvoiceImage`
// copia la imagen a `invoices/` con sus bytes y su extensión (o `.jpg`) y la
// compra conserva esa ruta. Es lo que hace el formulario de compra tras elegir
// la foto (`purchase_form_screen.dart`, `_save`). La cámara no se ejercita
// aquí: sigue como límite declarado en #44.
//
// Criterio 2: en el historial de compras, «Ver factura» sólo aparece cuando la
// compra tiene fotografía, abre el diálogo con esa imagen y, si el archivo ya
// no existe, lo dice en lugar de abrir un diálogo vacío.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/agro_repository.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/domain/models.dart';
import 'package:agroquimicos/presentation/screens/purchases_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// Dependencia transitiva de `path_provider`: se usa sólo para sustituir la
// implementación de plataforma en la prueba, sin tocar `pubspec.yaml`.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_app_access.dart';

class _WorkspacePathProvider extends PathProviderPlatform {
  _WorkspacePathProvider(this.directory);
  final String directory;

  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
  @override
  Future<String?> getTemporaryPath() async => directory;
  @override
  Future<String?> getApplicationSupportPath() async => directory;
}

/// PNG válido de 1×1: el diálogo lo decodifica de verdad, sin binarios
/// versionados.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  sqfliteFfiInit();

  late Directory workspace;
  late Directory picked;
  late AppDatabase database;
  late AgroRepository repo;
  late int family;
  late int supplier;
  late int campaign;
  late int product;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('agro_rec008_');
    // La foto elegida vive fuera de la carpeta privada, como la que entrega
    // el selector del sistema.
    picked = await Directory(p.join(workspace.path, 'galeria'))
        .create(recursive: true);
    PathProviderPlatform.instance = _WorkspacePathProvider(
      p.join(workspace.path, 'documentos'),
    );
    database = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repo = AgroRepository(database);
    family = await repo.addPerson(name: 'Familiar', role: PersonRole.family);
    supplier = await repo.addSupplier(name: 'Proveedor');
    campaign = await repo.addCampaign(
      name: 'Campaña',
      start: DateTime.utc(2026, 1, 1),
    );
    product = await repo.addProduct(name: 'Glifosato');
  });

  tearDown(() async {
    await database.close();
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      // En Windows un archivo recién abierto puede seguir retenido; es temporal.
    }
  });

  String invoicesPath() => p.join(workspace.path, 'documentos', 'invoices');

  Future<File> pickedPhoto(String name, List<int> bytes) =>
      File(p.join(picked.path, name)).writeAsBytes(bytes, flush: true);

  Future<int> purchase({required String invoice, String? imagePath}) =>
      repo.confirmPurchase(
        PurchaseDraft(
          supplierId: supplier,
          campaignId: campaign,
          purchaseDate: DateTime.utc(2026, 1, 10),
          invoiceNumber: invoice,
          invoiceImagePath: imagePath,
          items: [
            PurchaseItemDraft(
              productId: product,
              quantityBase: 1000,
              currency: CurrencyCode.bob,
              originalUnitPriceMinor: 4500,
              allocations: [
                AllocationDraft(personId: family, quantityBase: 1000),
              ],
            ),
          ],
        ),
      );

  group('storeInvoiceImage', () {
    test(
      'copia la foto a invoices/ con sus bytes y su extensión, sin moverla',
      () async {
        final bytes = List<int>.generate(4096, (i) => (i * 7) % 251);
        final source = await pickedPhoto('factura.png', bytes);

        final stored = await repo.storeInvoiceImage(source.path);

        expect(p.dirname(stored), invoicesPath());
        expect(p.basename(stored), matches(RegExp(r'^invoice_\d+\.png$')));
        expect(await File(stored).readAsBytes(), bytes);
        expect(
          await source.exists(),
          isTrue,
          reason: 'se copia: el original del selector no se toca',
        );
      },
    );

    test('sin extensión guarda .jpg', () async {
      final source = await pickedPhoto('captura', _png);

      final stored = await repo.storeInvoiceImage(source.path);

      expect(p.basename(stored), matches(RegExp(r'^invoice_\d+\.jpg$')));
      expect(await File(stored).readAsBytes(), _png);
    });

    test('la compra conserva la ruta guardada y apunta al archivo', () async {
      final source = await pickedPhoto('factura.jpg', _png);
      final stored = await repo.storeInvoiceImage(source.path);

      final id = await purchase(invoice: 'F-001', imagePath: stored);

      final row = (await repo.purchases()).singleWhere((r) => r['id'] == id);
      expect(row['invoice_image_path'], stored);
      expect(await File(stored).exists(), isTrue);
    });
  });

  group('visor en el historial de compras', () {
    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> waitFor(WidgetTester tester, Finder finder) async {
      for (var round = 0; round < 60; round++) {
        if (finder.evaluate().isNotEmpty) return;
        await settle(tester);
      }
    }

    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            activatedInstallationForTests(),
          ],
          child: const MaterialApp(home: Scaffold(body: PurchasesScreen())),
        ),
      );
      await waitFor(tester, find.textContaining('Proveedor · '));
    }

    /// Abre el menú de la tarjeta de la compra con [invoice].
    Future<void> openMenu(WidgetTester tester, String invoice) async {
      final card = find.ancestor(
        of: find.text('Proveedor · $invoice'),
        matching: find.byType(Card),
      );
      final menu = find.descendant(
        of: card,
        matching: find.byType(PopupMenuButton<String>),
      );
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await settle(tester);
    }

    testWidgets('«Ver factura» sólo aparece en la compra con fotografía', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final source = await pickedPhoto('factura.png', _png);
        await purchase(
          invoice: 'F-FOTO',
          imagePath: await repo.storeInvoiceImage(source.path),
        );
        await purchase(invoice: 'F-SIN');
      });
      await pumpScreen(tester);

      await openMenu(tester, 'F-SIN');
      expect(find.text('Registrar pago'), findsOneWidget);
      expect(find.text('Ver factura'), findsNothing);
      await tester.tapAt(Offset.zero);
      await settle(tester);

      await openMenu(tester, 'F-FOTO');
      expect(find.text('Ver factura'), findsOneWidget);
    });

    testWidgets('abre el diálogo con la imagen guardada y se cierra', (
      tester,
    ) async {
      late String stored;
      await tester.runAsync(() async {
        final source = await pickedPhoto('factura.png', _png);
        stored = await repo.storeInvoiceImage(source.path);
        await purchase(invoice: 'F-FOTO', imagePath: stored);
      });
      await pumpScreen(tester);

      await openMenu(tester, 'F-FOTO');
      await tester.tap(find.text('Ver factura'));
      await waitFor(tester, find.byType(AlertDialog));

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('Factura')),
        findsOneWidget,
      );
      final image = tester.widget<Image>(
        find.descendant(of: dialog, matching: find.byType(Image)),
      );
      expect(image.image, isA<FileImage>());
      expect((image.image as FileImage).file.path, stored);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Cerrar'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('si la foto ya no existe lo avisa y no abre el diálogo', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final source = await pickedPhoto('factura.png', _png);
        final stored = await repo.storeInvoiceImage(source.path);
        await purchase(invoice: 'F-FOTO', imagePath: stored);
        await File(stored).delete();
      });
      await pumpScreen(tester);

      await openMenu(tester, 'F-FOTO');
      await tester.tap(find.text('Ver factura'));
      const message =
          'La imagen de factura ya no está disponible en este dispositivo.';
      await waitFor(tester, find.text(message));

      expect(find.text(message), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
