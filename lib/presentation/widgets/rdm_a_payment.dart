/// Hoja «Registrar pago» de una cuenta (lámina Pago), compartida por Cuentas,
/// Personas y el detalle de persona. Sólo pide el importe: quién paga, en qué
/// campaña se registra y cómo se imputa los decide la pantalla que la abre y
/// `registerAccountPayment`, como hasta ahora.
library;

import 'package:flutter/material.dart';

import '../../domain/account_texts.dart';
import '../../domain/numeric_input.dart';
import '../theme/agro_theme.dart';
import 'agro_ui.dart';

/// Abre la hoja y devuelve el importe en centavos, o `null` si se cancela.
///
/// [netMinor] es el saldo neto de todas las campañas (D-04 §2.4): con deuda
/// ofrece «Pagar todo» y dice cuánto quedará. Con [ownRecord] (pago propio
/// del titular, criterio Q-2) no hay saldo que cobrar ni imputación FIFO.
Future<int?> showAccountPaymentSheet(
  BuildContext context, {
  required String personName,
  required String registration,
  required int netMinor,
  bool ownRecord = false,
}) => showModalBottomSheet<int>(
  context: context,
  // Por encima de la barra inferior y del botón flotante del shell.
  useRootNavigator: true,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: AgroColors.canvas,
  builder: (_) => _PaymentSheet(
    personName: personName,
    registration: registration,
    netMinor: netMinor,
    ownRecord: ownRecord,
  ),
);

/// Contenido de la hoja. Es dueña de su `TextEditingController` y lo libera
/// en `dispose()` (UIBUG-005).
///
/// Conserva lo del diálogo anterior:
///  * **UIBUG-012** — dice a quién se paga y en qué campaña se registra;
///  * **UIBUG-065** — un importe no interpretable explica el formato en vez
///    de valer 0;
///  * **UIBUG-003** — el importe se lee con el convenio es-BO;
///  * **A4 (2026-10-30)** — el campo empieza vacío.
class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({
    required this.personName,
    required this.registration,
    required this.netMinor,
    required this.ownRecord,
  });

  final String personName;
  final String registration;
  final int netMinor;
  final bool ownRecord;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = parseNumericInput(_amount.text);
    switch (parsed.status) {
      case NumericInputStatus.empty:
        setState(() => _error = 'Escriba el importe.');
      case NumericInputStatus.ambiguous:
      case NumericInputStatus.malformed:
        // El mensaje describe el problema real y cómo escribirlo bien, en vez
        // de convertir la cadena en 0 y culpar al importe (UIBUG-065).
        setState(() => _error = parsed.message);
      case NumericInputStatus.valid:
        final minor = (parsed.value! * 100).round();
        if (minor <= 0) {
          setState(() => _error = 'El importe debe ser mayor a cero.');
          return;
        }
        Navigator.pop(context, minor);
    }
  }

  /// «Quedará debiendo …» con lo escrito, sólo como guía: la imputación real
  /// la hace el repositorio (a la deuda más antigua de cualquier campaña).
  String? get _after {
    if (widget.ownRecord || widget.netMinor <= 0) return null;
    final parsed = parseNumericInput(_amount.text);
    if (!parsed.isValid) return null;
    final rest = widget.netMinor - (parsed.value! * 100).round();
    if (rest > 0) return 'Quedará debiendo ${bob(rest)}';
    if (rest < 0) return 'Quedará a favor ${bob(-rest)}';
    return 'Quedará al día';
  }

  @override
  Widget build(BuildContext context) {
    final after = _after;
    final net = widget.netMinor;
    return SafeArea(
      child: Padding(
        // La hoja se encoge con el teclado en vez de quedar debajo.
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        // Los botones quedan fijos al pie, fuera de lo que se desplaza: con
        // el teclado abierto y un mensaje de error largo, «Registrar» sigue
        // a la vista (A4, 2026-10-30).
        child: Column(
          key: const Key('payment-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Registrar pago', style: AgroText.sheetTitle),
                    // Contexto de la operación: sin esto es fácil abrir la tarjeta
                    // equivocada en una lista larga y cobrar a quien no era
                    // (UIBUG-012).
                    Text(
                      widget.personName,
                      key: const Key('payment-person'),
                      style: AgroText.value,
                    ),
                    const SizedBox(height: 2),
                    Text(widget.registration, style: AgroText.detail),
                    Text(
                      widget.ownRecord
                          ? ownPaymentDialogText
                          : dialogNetText(net),
                      style: AgroText.detail,
                    ),
                    // El pago propio no se aplica a ninguna deuda: sin la línea FIFO.
                    if (!widget.ownRecord) ...[
                      Text(dialogFifoText, style: AgroText.detail),
                      Text(dialogCreditText, style: AgroText.detail),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('payment-amount'),
                      controller: _amount,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() => _error = null),
                      onSubmitted: (_) => _submit(),
                      style: AgroText.input.copyWith(
                        fontSize: 34,
                        height: 40 / 34,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Importe del pago',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        suffixText: 'Bs',
                        suffixStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AgroColors.muted,
                        ),
                        errorText: _error,
                        // Un mensaje de formato ocupa varias líneas.
                        errorMaxLines: 4,
                      ),
                    ),
                    if (!widget.ownRecord && net > 0) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Sólo escribe el importe: no registra nada.
                          ActionChip(
                            key: const Key('payment-all'),
                            backgroundColor: AgroColors.lime,
                            side: BorderSide.none,
                            shape: const StadiumBorder(),
                            label: Text(
                              'Pagar todo: ${bob(net)}',
                              style: const TextStyle(
                                fontFamily: AgroFonts.body,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AgroColors.ink,
                              ),
                            ),
                            onPressed: () => setState(() {
                              _amount.text = formatForInput(net / 100);
                              _error = null;
                            }),
                          ),
                          if (after != null)
                            Text(
                              after,
                              key: const Key('payment-after'),
                              style: AgroText.detail.copyWith(
                                color: AgroColors.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            PrimaryActionButton(
              key: const Key('payment-submit'),
              label: 'Registrar',
              icon: Icons.check,
              iconFirst: true,
              onPressed: _submit,
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const Key('payment-cancel'),
              style: TextButton.styleFrom(
                foregroundColor: AgroColors.ink,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
