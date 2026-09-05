import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/app_log.dart';
import '../../domain/numeric_input.dart';

export '../../domain/numeric_input.dart'
    show
        NumericInputResult,
        NumericInputStatus,
        formatForInput,
        parseNumericInput;
export '../../domain/labels.dart'
    show
        campaignStatusLabel,
        conceptLabel,
        operationStatusLabel,
        personRoleLabel,
        transactionTypeLabel;
export '../../domain/text_search.dart' show matchesSearch, normalizeForSearch;

/// Espacio que el contenido desplazable debe reservar por debajo.
///
/// Lo publica [AppShell] para que **cada pantalla no invente su propio relleno**
/// bajo el `FloatingActionButton` (UIBUG-008/009). Las rutas que viven fuera del
/// shell —los cuatro formularios— no tienen FAB y no encuentran este widget, así
/// que reservan 0.
class ContentInsets extends InheritedWidget {
  const ContentInsets({
    super.key,
    required this.bottomReserve,
    required super.child,
  });

  /// Alto que ocupan el FAB y su margen.
  final double bottomReserve;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ContentInsets>()
          ?.bottomReserve ??
      0;

  @override
  bool updateShouldNotify(ContentInsets oldWidget) =>
      oldWidget.bottomReserve != bottomReserve;
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.action,
  });
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    // Una pantalla a la que se llegó apilando debe ofrecer siempre una salida:
    // sin esto, las de detalle eran callejones sin salida (UIBUG-004A).
    //
    // Se pregunta al ROUTER, no al `Navigator`: con `ShellRoute` la pila que
    // importa es la de go_router, y el `Navigator` más cercano no la refleja.
    // Los cuatro formularios no usan `PageFrame` (tienen `AppBar` propia), así
    // que no aparecen dos flechas.
    //
    // `maybeOf` y no `of`: varias suites montan una pantalla suelta sin router,
    // y una cabecera no debe hacer estallar la pantalla por eso.
    final router = GoRouter.maybeOf(context);
    final canPop = router?.canPop() ?? false;
    // El contenido termina por encima del FAB y del teclado, en vez de quedar
    // tapado justo al agotarse el scroll (UIBUG-008, UIBUG-009).
    final bottom =
        24 +
        ContentInsets.of(context) +
        MediaQuery.viewInsetsOf(context).bottom;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(canPop ? 4 : 16, 16, 16, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (canPop)
                  IconButton(
                    tooltip: 'Volver',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => router!.pop(),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null) action!,
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, bottom),
          sliver: SliverToBoxAdapter(child: child),
        ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(40),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

void showError(BuildContext context, Object error) {
  // Punto único por el que pasan todos los errores que ve el usuario: es el
  // mejor sitio para dejar rastro sin instrumentar cada pantalla.
  AppLog.error('Error mostrado al usuario', error: error);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(friendlyError(error)),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

void showSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Confirmación para acciones destructivas o contablemente irreversibles.
///
/// Las reversiones ajustan inventario y saldos y no se pueden deshacer desde la
/// interfaz, así que no deben ejecutarse con un solo toque accidental. El
/// [detail] debe describir *qué* registro se ve afectado y *qué* efecto tendrá,
/// para que la confirmación sea informada y no un trámite.
Future<bool> confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String detail,
  String confirmLabel = 'Revertir',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_outlined),
        title: Text(title),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;

/// Interpreta [value] con convenio es-BO: la coma separa decimales y el punto
/// separa miles, igual que la salida de `formatBob`/`formatQuantity`.
///
/// Devuelve `null` si la cadena está vacía, es ambigua o no respeta el
/// convenio. La regla vive en [parseNumericInput] (`lib/domain/numeric_input.dart`,
/// especificada en `docs/44_NUMERIC_INPUT_SPEC.md`); aquí sólo se adapta al
/// `num?` que esperan las pantallas.
num? tryParseDecimal(String value) => parseNumericInput(value).value;

int? tryParseMinor(String value) {
  final parsed = tryParseDecimal(value);
  return parsed == null ? null : (parsed * 100).round();
}

int? tryParseBase(String value) {
  final parsed = tryParseDecimal(value);
  return parsed == null ? null : (parsed * 1000).round();
}

int parseMinor(String value) => tryParseMinor(value) ?? 0;
int parseBase(String value) => tryParseBase(value) ?? 0;

String friendlyError(Object error) {
  final message = error.toString().replaceFirst('BusinessRuleException: ', '');
  if (message.contains('FormatException')) {
    return 'Revise los valores numéricos ingresados.';
  }
  if (message.contains('StateError')) {
    return 'Falta seleccionar información requerida.';
  }
  // Los errores de SQLite llegaban al usuario en inglés y con la sentencia
  // dentro (UIBUG-015 / KI-16). El detalle técnico ya queda en el log local, que
  // es donde sirve; aquí se dice qué pasó y qué hacer.
  if (message.contains('DatabaseException') ||
      message.contains('SQLITE') ||
      message.contains('sqlite')) {
    if (message.toUpperCase().contains('UNIQUE')) {
      return 'Ese registro ya existe. Revise los datos e inténtelo de nuevo.';
    }
    if (message.toUpperCase().contains('FOREIGN KEY')) {
      return 'No se puede completar: hay información relacionada que lo impide.';
    }
    return 'No se pudo completar la operación sobre los datos. Inténtelo de '
        'nuevo; si el problema persiste, exporte un respaldo y reinicie.';
  }
  return message;
}
