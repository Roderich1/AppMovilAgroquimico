/// Entrada a la voz desde Operaciones (F09): elegir qué se va a dictar.
///
/// Cada opción abre un borrador que no registra nada hasta confirmarlo con un
/// toque. Los formularios manuales siguen siendo la alternativa equivalente.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/common.dart';

/// Ruta de la entrada y de cada borrador. Viven dentro del shell, como el
/// resto de subdestinos de Operaciones: se llega apilando y Atrás vuelve.
const voiceEntryPath = '/voz';
const voicePurchasePath = '/compras/voz';
const voicePlanPath = '/planificacion/voz';
const voiceApplicationPath = '/aplicaciones/voz';

class VoiceEntryScreen extends StatelessWidget {
  const VoiceEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final options = [
      (
        key: 'voz-entrada-compra',
        title: 'Compra por voz',
        subtitle: 'Productos, cantidades, precios y proveedor',
        icon: Icons.shopping_bag_outlined,
        path: voicePurchasePath,
      ),
      (
        key: 'voz-entrada-plan',
        title: 'Planificación por voz',
        subtitle: 'Chaco, área y dosis por hectárea',
        icon: Icons.event_note_outlined,
        path: voicePlanPath,
      ),
      (
        key: 'voz-entrada-aplicacion',
        title: 'Aplicación por voz',
        subtitle: 'Productos y cantidades aplicadas en un chaco',
        icon: Icons.agriculture_outlined,
        path: voiceApplicationPath,
      ),
    ];
    return PageFrame(
      title: 'Registrar por voz',
      subtitle:
          'La voz prepara un borrador para revisar. Nada se registra hasta '
          'que usted lo confirme. También puede usar los formularios.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in options)
            Card(
              child: ListTile(
                key: Key(option.key),
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(child: Icon(option.icon)),
                title: Text(
                  option.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(option.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(option.path),
              ),
            ),
        ],
      ),
    );
  }
}
