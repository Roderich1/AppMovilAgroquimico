import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/operation_mode.dart';
import '../../operation_mode_controller.dart';
import '../widgets/common.dart';

/// «Más»: las funciones que se usan de vez en cuando, agrupadas en un solo
/// acceso para que Inicio y Operaciones queden con lo del trabajo diario
/// (ajuste tras el piloto X01, 2026-10-25). Ningún acceso se pierde y cada
/// pantalla conserva sus guardas: aquí sólo se navega.
///
/// Las alertas de sesión, sincronización y recuperación siguen en Inicio; no
/// se esconden aquí. F09 (voz) sigue en pausa: su entrada queda al final.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(operationModeProvider);
    final actions =
        <({String title, String subtitle, String path, IconData icon})>[
          (
            title: 'Reportes',
            subtitle: 'Exportar inventario, costos y cuentas a CSV o PDF',
            path: '/reportes',
            icon: Icons.summarize_outlined,
          ),
          (
            title: 'Administrar datos',
            subtitle: 'Campañas, chacos, productos, proveedores y personas',
            path: '/catalogos',
            icon: Icons.settings_outlined,
          ),
          (
            title: 'Modo de uso',
            subtitle: switch (mode) {
              OperationMode.personal => 'Ahora: inventario propio',
              OperationMode.shared => 'Ahora: inventario compartido',
              null => 'Inventario propio o compartido',
            },
            path: '/modo',
            icon: Icons.tune_outlined,
          ),
          (
            title: 'Vínculos con el sindicato',
            subtitle: 'Campaña y productos emparejados con los del sindicato',
            path: '/sindicato/vinculos',
            icon: Icons.link_outlined,
          ),
          (
            title: 'Respaldo en la nube',
            subtitle: 'Copia privada y cifrada en el servidor',
            path: '/respaldo-remoto',
            icon: Icons.cloud_upload_outlined,
          ),
          (
            title: 'Copias de seguridad en este teléfono',
            subtitle:
                'Exportar y restaurar un archivo: en Cuentas, menú de la '
                'carpeta',
            path: '/liquidacion',
            icon: Icons.folder_outlined,
          ),
          (
            title: 'PIN del titular',
            subtitle: 'Crear o cambiar el PIN que autoriza reversiones',
            path: '/titular/pin',
            icon: Icons.pin_outlined,
          ),
          // RF-03: compras y aplicaciones con fecha de una campaña cerrada,
          // pendientes de que el titular las confirme o las rechace.
          (
            title: 'Operaciones tardías',
            subtitle:
                'Compras y aplicaciones de campañas cerradas, en revisión',
            path: '/operaciones/tardias',
            icon: Icons.history_edu_outlined,
          ),
          // F09, al final. No promete registrar nada por sí sola: lleva a
          // borradores que se revisan y se confirman con un toque.
          (
            title: 'Registrar por voz',
            subtitle: 'Dictar una compra, un plan o una aplicación y revisarlo',
            path: '/voz',
            icon: Icons.mic_none_outlined,
          ),
        ];
    return PageFrame(
      title: 'Más',
      subtitle: 'Lo que se usa de vez en cuando.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 700
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final action in actions)
                SizedBox(
                  width: width,
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(child: Icon(action.icon)),
                      title: Text(
                        action.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(action.subtitle),
                      trailing: const Icon(Icons.chevron_right),
                      // Se APILAN: Atrás vuelve aquí (UIBUG-004A).
                      onTap: () => context.push(action.path),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
