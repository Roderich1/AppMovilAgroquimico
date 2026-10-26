import 'package:flutter/material.dart';

import '../../domain/campaign_calendar.dart';
import '../../domain/models.dart';

/// Medio y fecha de un pago al proveedor, **visibles y corregibles**.
///
/// La tabla exige un medio y una fecha; la interfaz no los inventa. El medio
/// empieza en «Sin indicar» (un valor explícito, no un medio supuesto) y la
/// fecha en [day], que quien lo muestra explica con [dayHint] («(hoy)», «(el
/// día de la compra)»). El selector de fecha no ofrece el futuro (un pago ya
/// hecho no es futuro); sí admite días anteriores a la compra (anticipos).
class ProviderPaymentFields extends StatelessWidget {
  const ProviderPaymentFields({
    super.key,
    required this.method,
    required this.onMethodChanged,
    required this.day,
    required this.dayHint,
    required this.onDayChanged,
    this.enabled = true,
  });

  final PaymentMethod method;
  final ValueChanged<PaymentMethod> onMethodChanged;

  /// Día local `aaaa-mm-dd` del pago.
  final String day;
  final String dayHint;
  final ValueChanged<String> onDayChanged;
  final bool enabled;

  Future<void> _pickDay(BuildContext context) async {
    final now = DateTime.now();
    final initial = startOfLocalDay(day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      // Si el día mostrado quedara después del reloj (reloj atrasado o base
      // restaurada), el selector no debe abrirse con un rango inválido.
      lastDate: now.isBefore(initial) ? initial : now,
      helpText: 'Fecha del pago',
    );
    if (picked != null) onDayChanged(localDay(picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('¿Cómo pagaste?'),
        const SizedBox(height: 6),
        // Chips en `Wrap`: con fuente ampliada pasan a otra línea en vez de
        // recortarse. Siempre hay una elegida: «Sin indicar» por defecto.
        Wrap(
          key: const Key('payment-method'),
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final option in PaymentMethod.values)
              ChoiceChip(
                key: Key('payment-method-${option.name}'),
                label: Text(option.label),
                selected: option == method,
                onSelected: enabled
                    ? (selected) {
                        if (selected) onMethodChanged(option);
                      }
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 4),
        ListTile(
          key: const Key('payment-date'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: const Text('Fecha del pago'),
          subtitle: Text(
            '${displayDay(day)}$dayHint',
            style: theme.textTheme.bodyMedium,
          ),
          trailing: enabled ? const Text('Cambiar') : null,
          onTap: enabled ? () => _pickDay(context) : null,
        ),
      ],
    );
  }
}
