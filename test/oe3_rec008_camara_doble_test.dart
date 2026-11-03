// OE3, cierre HOST de #44 (REC-008, foto de factura): el camino de la
// **cámara** del formulario de compra, con un DOBLE DE PRUEBA de la
// plataforma de `image_picker` (`_CameraDouble`). No hay cámara física: el
// doble sustituye a `ImagePickerPlatform.instance`, registra qué pidió la app y
// devuelve un PNG sintético escrito en una carpeta temporal, como haría el
// selector del sistema tras tomar la foto. Lo que se prueba es la parte de la
// app: el botón «Cámara» pide `ImageSource.camera` con la calidad y el ancho
// que usa el formulario, la miniatura aparece, y al confirmar la compra la
// foto se copia a `<documentos>/invoices/` con sus mismos bytes y la compra
// guarda esa ruta. También: cancelar la cámara no adjunta nada, y una
// negación de permiso se avisa y la compra se guarda sin foto.
//
// Lo que este doble NO prueba: el permiso real de Android, el intent de
// captura, la rotación o la recodificación del JPEG por el sistema, ni el
// comportamiento de un modelo de teléfono. Eso sólo lo mide DEVICE, y la
// cámara no se ejercitó en ningún teléfono (#44).
//
// Pruebas de HOST (widget sobre `AgroApp` completa, sqflite_common_ffi).
import 'dart:convert';
import 'dart:io';

import 'package:agroquimicos/app.dart';
import 'package:agroquimicos/data/app_database.dart';
import 'package:agroquimicos/presentation/widgets/adaptive_entity_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Dependencias transitivas de `image_picker` y `path_provider`: se usan sólo
// para sustituir la implementación de plataforma en la prueba, sin tocar
// `pubspec.yaml` (mismo criterio que `rec_008_invoice_viewer_test.dart`). La
// interfaz de plataforma también exporta `XFile` e `ImageSource`.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/f04_mode_ui_harness.dart';

typedef Row = Map<String, Object?>;

/// PNG válido de 1×1, sin binarios versionados.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
  '60e6kgAAAABJRU5ErkJggg==',
);

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

/// Doble de prueba de la plataforma de `image_picker`. No es una cámara:
/// devuelve lo que la prueba le indique y registra cada petición.
class _CameraDouble extends ImagePickerPlatform {
  _CameraDouble(this.answer);

  /// Respuesta a la próxima petición: un archivo, `null` (cancelada) o una
  /// excepción (permiso negado).
  Future<XFile?> Function() answer;
  final requests = <(ImageSource, ImagePickerOptions)>[];

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) {
    requests.add((source, options));
    return answer();
  }
}

void main() {
  sqfliteFfiInit();

  late Directory workspace;
  late _CameraDouble camera;

  /// Carpeta de trabajo, plataformas sustituidas y su restauración.
  Future<void> setUpPlatforms(WidgetTester tester) async {
    workspace = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('agro_oe3_camara_'),
    ))!;
    final previousPaths = PathProviderPlatform.instance;
    final previousPicker = ImagePickerPlatform.instance;
    PathProviderPlatform.instance = _WorkspacePathProvider(
      p.join(workspace.path, 'documentos'),
    );
    camera = _CameraDouble(() async => null);
    ImagePickerPlatform.instance = camera;
    addTearDown(() async {
      PathProviderPlatform.instance = previousPaths;
      ImagePickerPlatform.instance = previousPicker;
      await tester.runAsync(() async {
        try {
          await workspace.delete(recursive: true);
        } on FileSystemException {
          // En Windows un archivo recién abierto puede seguir retenido.
        }
      });
    });
  }

  /// Foto que «entrega» la cámara: fuera de la carpeta privada de la app.
  Future<String> capturedPhoto(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final dir = await Directory(p.join(workspace.path, 'camara'))
            .create(recursive: true);
        final file = File(p.join(dir.path, 'captura_sintetica.png'));
        await file.writeAsBytes(_png, flush: true);
        return file.path;
      }))!;

  Finder picker(String label) => find.byWidgetPredicate(
    (w) => w is AdaptiveEntityPicker<Row> && w.label == label,
  );

  Future<void> choose(WidgetTester tester, String label, String name) async {
    final widget = tester.widget<AdaptiveEntityPicker<Row>>(picker(label));
    widget.onChanged(
      widget.items.firstWhere((item) => widget.labelOf(item) == name),
    );
    await settle(tester);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  Future<List<Row>> purchases(
    WidgetTester tester,
    AppDatabase database,
  ) async => (await tester.runAsync(
    () async => (await database.database).query('purchases'),
  ))!;

  /// Formulario en el paso 2 con «No, todavía no» y los detalles abiertos.
  Future<AppDatabase> openReviewWithDetails(
    WidgetTester tester,
    String name,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await setUpPlatforms(tester);
    final s = await activatedHousehold(tester, name);
    final c = await pumpModeApp(tester, s.database);
    c.read(routerProvider).push('/compras/nueva');
    await waitFor(tester, field('Cantidad comprada'));
    await settle(tester);
    await choose(tester, 'Proveedor', 'Proveedor');
    await choose(tester, 'Producto', 'Glifosato');
    await tester.enterText(field('Cantidad comprada'), '2');
    await tester.enterText(field('Precio BOB/L'), '45');
    await tapKey(tester, 'purchase-alloc-single-0');
    await choose(tester, 'Persona', 'Titular');
    await tapKey(tester, 'purchase-continue');
    await tester.tap(find.byKey(const Key('purchase-paid-no')));
    await settle(tester);
    await tapKey(tester, 'purchase-details');
    expect(find.text('Cámara'), findsOneWidget);
    return s.database;
  }

  Future<void> confirmAndWait(WidgetTester tester) async {
    await tapKey(tester, 'purchase-confirm');
    await waitUntil(
      tester,
      'guardar la compra y cerrar el formulario',
      () => find.byKey(const Key('purchase-confirm')).evaluate().isEmpty,
      state: () => find.byType(SnackBar).evaluate().isEmpty
          ? 'formulario abierto, sin aviso'
          : 'formulario abierto con un aviso',
    );
  }

  Finder thumbnailOf(String path) => find.byWidgetPredicate(
    (w) =>
        w is Image &&
        w.image is FileImage &&
        (w.image as FileImage).file.path == path,
  );

  testWidgets('cámara (doble): pide ImageSource.camera, muestra la miniatura y '
      'al confirmar copia la foto a invoices/ con sus bytes', (tester) async {
    final database = await openReviewWithDetails(tester, 'camara-ok');
    final photo = await capturedPhoto(tester);
    camera.answer = () async => XFile(photo);

    await tester.tap(find.text('Cámara'));
    await settle(tester);

    expect(camera.requests, hasLength(1));
    final (source, options) = camera.requests.single;
    expect(source, ImageSource.camera);
    expect(options.imageQuality, 82);
    expect(options.maxWidth, 1800);
    expect(thumbnailOf(photo), findsOneWidget);

    await confirmAndWait(tester);
    final purchase = (await purchases(tester, database)).single;
    final stored = purchase['invoice_image_path'] as String?;
    expect(stored, isNotNull);
    expect(
      p.dirname(stored!),
      p.join(workspace.path, 'documentos', 'invoices'),
    );
    expect(p.basename(stored), matches(RegExp(r'^invoice_\d+\.png$')));
    expect(stored, isNot(photo));
    final bytes = await tester.runAsync(() => File(stored).readAsBytes());
    expect(bytes, _png);
    // La cámara se pidió una sola vez; la galería, nunca.
    expect(camera.requests.map((r) => r.$1), [ImageSource.camera]);
  });

  testWidgets('cámara cancelada (doble devuelve null): no se adjunta nada y la '
      'compra se guarda sin foto', (tester) async {
    final database = await openReviewWithDetails(tester, 'camara-cancelada');
    camera.answer = () async => null;

    await tester.tap(find.text('Cámara'));
    await settle(tester);

    expect(camera.requests.single.$1, ImageSource.camera);
    expect(
      find.byWidgetPredicate((w) => w is Image && w.image is FileImage),
      findsNothing,
    );
    await confirmAndWait(tester);
    final purchase = (await purchases(tester, database)).single;
    expect(purchase['invoice_image_path'], isNull);
  });

  testWidgets('permiso de cámara negado (doble lanza PlatformException): se '
      'avisa y la compra se guarda sin foto', (tester) async {
    final database = await openReviewWithDetails(tester, 'camara-negada');
    camera.answer = () async => throw PlatformException(
      code: 'camera_access_denied',
      message: 'detalle interno del doble',
    );

    await tester.tap(find.text('Cámara'));
    await settle(tester);

    expect(camera.requests.single.$1, ImageSource.camera);
    expect(
      find.textContaining(
        'No se pudo adjuntar la factura. Revise los permisos.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('detalle interno del doble'), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is Image && w.image is FileImage),
      findsNothing,
    );
    await confirmAndWait(tester);
    final purchase = (await purchases(tester, database)).single;
    expect(purchase['invoice_image_path'], isNull);
  });
}
