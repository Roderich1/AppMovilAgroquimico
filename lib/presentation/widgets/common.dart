import 'package:flutter/material.dart';

import '../../data/app_log.dart';

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
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        sliver: SliverToBoxAdapter(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        sliver: SliverToBoxAdapter(child: child),
      ),
    ],
  );
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

num? tryParseDecimal(String value) {
  final normalized = value.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  return num.tryParse(normalized);
}

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
  return message;
}
