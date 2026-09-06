import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Dónde viven las fotografías de factura.
///
/// Un único sitio que lo decida: lo necesitan tanto [AgroRepository], que
/// guarda la foto al confirmar una compra, como [BackupService], que ahora
/// tiene que meterlas en el respaldo y devolverlas a su sitio al restaurar.
/// Cuando cada uno lo calculaba por su cuenta bastaba con que uno cambiara
/// para que el respaldo dejara de encontrar los archivos.
///
/// Crea la carpeta si no existe.
Future<Directory> resolveInvoicesDirectory() async {
  final documents = await getApplicationDocumentsDirectory();
  final invoices = Directory(p.join(documents.path, 'invoices'));
  await invoices.create(recursive: true);
  return invoices;
}
