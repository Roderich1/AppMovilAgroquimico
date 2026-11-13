import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/agro_theme.dart';
import 'agro_ui.dart';
import 'common.dart' show showSuccess;
import '../screens/ind_home.dart' show indProvidersRoute;

/// Cambia cada vez que se cierra un formulario abierto desde la hoja
/// «Registrar». Las pestañas con historial o existencias (Actividad, Almacén)
/// lo escuchan para releer: la hoja abre los formularios por su cuenta y ellas
/// no se enteran de que se volvió (defecto del recorrido del 2026-11-12).
final registerRevisionProvider = NotifierProvider<RegisterRevision, int>(
  RegisterRevision.new,
);

class RegisterRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Hoja «Registrar» (rediseño, lámina «Registrar»), abierta desde el botón
/// flotante del shell.
///
/// Las mismas acciones de siempre: Compra y Aplicación arriba, en grande;
/// Plan de aplicación, Pago (en Cuentas, donde se elige la persona) y
/// Transferencia (sólo en inventario compartido); y «Completar por voz»,
/// que abre `/voz`, desde donde se elige el formulario con el panel de voz.
///
/// Los formularios están FUERA del ShellRoute y se apilan con `push`: con
/// `go` se reemplaza toda la pila y el botón atrás del formulario deja la
/// aplicación sin ninguna página que mostrar. `done` es el aviso al volver con
/// la operación guardada; nulo para los destinos que no son formularios.
Future<void> showRegisterSheet(
  BuildContext context, {
  required bool transfersEnabled,
  // Modo individual (lámina I-03): «Pago a un proveedor» en vez de «Pago»
  // en Cuentas (no hay cobros a personas) y la voz dentro de cada
  // formulario. Transferencia ya depende de [transfersEnabled].
  bool personalMode = false,
}) => showModalBottomSheet<void>(
  context: context,
  // Con la letra al 200 % la hoja crece y, si aun así no cabe, se desplaza.
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) {
    final large = MediaQuery.textScalerOf(sheetContext).scale(1) >= 1.5;
    void open(String path, {String? done}) {
      Navigator.of(sheetContext).pop();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) return;
        final saved = await context.push<bool>(path);
        if (!context.mounted) return;
        // Se relee aunque no diga «guardado»: desde `/voz` se llega a un
        // formulario y se vuelve sin resultado.
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(registerRevisionProvider.notifier).bump();
        if (done != null && saved == true) showSuccess(context, done);
      });
    }

    Widget row({
      required Key key,
      required IconData icon,
      required String label,
      String? hint,
      required VoidCallback onTap,
    }) => ListTile(
      key: key,
      minTileHeight: 64,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      // Con la letra muy grande el icono se omite: el nombre cabe entero en
      // una línea («Transferencia» se partía a 200 % en 360 dp).
      leading: large ? null : Icon(icon, color: AgroColors.ink),
      title: Text(label, style: AgroText.question),
      subtitle: hint == null ? null : Text(hint),
      trailing: const Icon(Icons.chevron_right, color: AgroColors.muted),
      onTap: onTap,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          key: const Key('register-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Registrar', style: AgroText.sheetTitle),
                  ),
                ),
                CircleIconButton(
                  key: const Key('register-close'),
                  icon: Icons.close,
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ActionTileRow(
              tiles: [
                ActionTile(
                  key: const Key('register-purchase'),
                  icon: Icons.shopping_bag_outlined,
                  label: 'Compra',
                  onTap: () =>
                      open('/compras/nueva', done: 'Compra registrada.'),
                ),
                ActionTile(
                  key: const Key('register-application'),
                  icon: Icons.spa_outlined,
                  label: 'Aplicación',
                  tone: ActionTileTone.ink,
                  onTap: () => open(
                    '/aplicaciones/nueva',
                    done: 'Aplicación registrada.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AgroGroup(
              children: [
                row(
                  key: const Key('register-plan'),
                  icon: Icons.event_note_outlined,
                  label: 'Plan de aplicación',
                  onTap: () =>
                      open('/planificacion/nueva', done: 'Plan guardado.'),
                ),
                if (personalMode)
                  row(
                    key: const Key('register-provider-payment'),
                    icon: Icons.payments_outlined,
                    label: 'Pago a un proveedor',
                    // Se paga desde la compra con saldo (Proveedores). Se
                    // APILA: Atrás vuelve a donde estaba (recorrido del
                    // emulador, 2026-11-13: con `go` no había flecha).
                    onTap: () => open(indProvidersRoute),
                  )
                else
                  row(
                    key: const Key('register-payment'),
                    icon: Icons.payments_outlined,
                    label: 'Pago',
                    hint: 'En Cuentas',
                    onTap: () {
                      // Pago se elige en Cuentas (no es un formulario): se va a
                      // la pantalla, sin apilar.
                      Navigator.of(sheetContext).pop();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (context.mounted) context.go('/liquidacion');
                      });
                    },
                  ),
                if (transfersEnabled)
                  row(
                    key: const Key('register-transfer'),
                    icon: Icons.swap_horiz,
                    label: 'Transferencia',
                    onTap: () => open(
                      '/transferencias/nueva',
                      done: 'Transferencia registrada.',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (personalMode)
              const Padding(
                key: Key('register-voice-note'),
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Compra, aplicación y plan se pueden completar por voz '
                  'dentro de su formulario.',
                  style: AgroText.detail,
                ),
              )
            else
              DashedPanel(
                key: const Key('register-voice'),
                onTap: () => open('/voz'),
                child: Row(
                  children: [
                    const Icon(Icons.mic_none, color: AgroColors.ink),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Completar por voz', style: AgroText.question),
                          // Con la letra muy grande la aclaración se omite para
                          // que todas las opciones quepan sin desplazarse.
                          if (MediaQuery.textScalerOf(context).scale(1) <
                              1.5) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Compra, aplicación o plan con el panel de voz',
                              style: AgroText.detail,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  },
);
