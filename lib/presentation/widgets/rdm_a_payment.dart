/// Acciones de una cuenta compartidas por Cuentas, Personas y el detalle de
/// persona: la hoja «Registrar pago» (lámina Pago), el estado de cuenta y
/// los movimientos propios a pantalla completa (láminas Cuenta y Propios).
///
/// Hoja «Registrar pago» de una cuenta (lámina Pago), compartida por Cuentas,
/// Personas y el detalle de persona. Sólo pide el importe: quién paga, en qué
/// campaña se registra y cómo se imputa los decide la pantalla que la abre y
/// `registerAccountPayment`, como hasta ahora.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app.dart';
import '../../domain/account_ledger.dart';
import '../../domain/campaign_calendar.dart';
import '../../domain/read_models.dart' show CampaignRead;
import '../../domain/reports/report_composer.dart' show ReportKind;

import '../../domain/account_texts.dart';
import '../theme/agro_theme.dart';
import 'rdm2_c_account_detail.dart';
import 'agro_ui.dart';
import 'common.dart';

/// Abre la hoja y devuelve el importe en centavos, o `null` si se cancela.
///
/// [netMinor] es el saldo neto de todas las campañas (D-04 §2.4): con deuda
/// ofrece «Pagar todo» y dice cuánto quedará. Ya no hay pago propio del
/// titular (decisión del autor del 2026-11-12, que revisa el criterio Q-2):
/// la hoja es sólo para cuentas por cobrar.
Future<int?> showAccountPaymentSheet(
  BuildContext context, {
  required String personName,
  required String registration,
  required int netMinor,
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
  });

  final String personName;
  final String registration;
  final int netMinor;

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
    if (widget.netMinor <= 0) return null;
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
                    Text(dialogNetText(net), style: AgroText.detail),
                    Text(dialogFifoText, style: AgroText.detail),
                    Text(dialogCreditText, style: AgroText.detail),
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
                    if (net > 0) ...[
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

/// Campaña de registro de un pago como período (para su texto y para
/// [recordAccountPayment]).
CampaignPeriod? rdmAPeriodOf(CampaignRead? campaign) => campaign == null
    ? null
    : CampaignPeriod.fromRow({
        'id': campaign.id,
        'name': campaign.name,
        'status': campaign.status,
        'start_date': campaign.startDate,
        'end_date': campaign.endDate,
      });

/// Pide el importe con la hoja y registra el pago de [person] en la campaña
/// [campaign] (sólo la de registro: la imputación va a la deuda más antigua
/// de cualquier campaña, D-04). Avisa del resultado. Devuelve `true` si quedó
/// registrado.
Future<bool> recordAccountPayment(
  BuildContext context,
  WidgetRef ref, {
  required AccountSummary person,
  required CampaignPeriod? campaign,
}) async {
  final amount = await showAccountPaymentSheet(
    context,
    personName: person.name,
    registration: registrationText(campaign, DateTime.now()),
    netMinor: person.account.netMinor,
  );
  if (amount == null || !context.mounted) return false;
  try {
    final payment = await ref
        .read(repositoryProvider)
        .registerAccountPayment(
          personId: person.personId,
          campaignId: campaign?.id,
          amountBobMinor: amount,
        );
    if (context.mounted) showSuccess(context, payment.message(person.name));
    return true;
  } catch (error) {
    if (context.mounted) showError(context, error);
    return false;
  }
}

/// Exportar desde un detalle: cierra el diálogo y abre Reportes situado en
/// el estado de cuenta de la persona, con el período elegido. Sin router (p.
/// ej. una pantalla montada sola en una prueba) no se ofrece.
void Function(int?)? _exportFrom(BuildContext context, int personId) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return null;
  return (campaignId) {
    Navigator.of(context, rootNavigator: true).pop();
    router.push(
      '/reportes?tipo=${ReportKind.accountStatement.name}'
      '&persona=$personId'
      '${campaignId == null ? '' : '&campana=$campaignId'}',
    );
  };
}

/// Estado de cuenta de una persona a pantalla completa (lámina Cuenta), con
/// la estructura común de los detalles (ronda 2, P2). Con [canPay] ofrece
/// «Registrar pago». Devuelve `true` si se registró un pago.
Future<bool> showAccountStatement(
  BuildContext context,
  WidgetRef ref, {
  required int personId,
  required String name,
  int? campaignId,
  bool canPay = false,
}) async {
  final statement = await ref
      .read(repositoryProvider)
      .accountStatement(personId, campaignId: campaignId);
  if (!context.mounted) return false;
  final outcome = Rdm2cDetailOutcome();
  final export = _exportFrom(context, personId);
  await showDialog<void>(
    context: context,
    builder: (_) => RdmAFullScreenSheet(
      overline: 'Cuenta',
      title: 'Estado de cuenta · $name',
      child: Rdm2cAccountDetail(
        statement: statement,
        campaignId: campaignId,
        own: false,
        outcome: outcome,
        // Nunca al titular vigente (decisión del autor del 2026-11-12).
        canPay: canPay && !statement.isCurrentOwner,
        onExport: export,
      ),
    ),
  );
  return outcome.recorded;
}

/// «Movimientos propios» del titular a pantalla completa (lámina Propios,
/// E-15 §B.2), con la misma estructura que el estado de cuenta y sin pago.
Future<void> showOwnMovements(
  BuildContext context,
  WidgetRef ref, {
  required int personId,
  required String name,
  int? campaignId,
}) async {
  final statement = await ref
      .read(repositoryProvider)
      .accountStatement(personId, campaignId: campaignId);
  if (!context.mounted) return;
  final export = _exportFrom(context, personId);
  await showDialog<void>(
    context: context,
    builder: (_) => RdmAFullScreenSheet(
      overline: 'Titular · no es deuda',
      title: 'Movimientos propios · $name',
      child: Rdm2cAccountDetail(
        statement: statement,
        campaignId: campaignId,
        own: true,
        outcome: Rdm2cDetailOutcome(),
        onExport: export,
      ),
    ),
  );
}

/// Estado de cuenta o movimientos propios a pantalla completa (láminas
/// Cuenta y Propios), con «Cerrar» arriba. Es un diálogo: no cambia la
/// navegación y se cierra como antes.
class RdmAFullScreenSheet extends StatelessWidget {
  const RdmAFullScreenSheet({
    super.key,
    required this.overline,
    required this.title,
    required this.child,
  });

  final String overline;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: AgroColors.canvas,
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(overline, style: AgroText.detail)),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AgroColors.ink,
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      label: const Text('Cerrar'),
                    ),
                  ],
                ),
                Semantics(header: true, child: Text(title, style: AgroText.h2)),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    ),
  );
}
