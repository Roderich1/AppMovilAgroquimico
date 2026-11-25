import 'campaign_calendar.dart';

class BusinessRuleException implements Exception {
  BusinessRuleException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Una acción confirmada con el PIN del titular falló **después** de
/// consumir la autorización, ya dentro de la transacción que escribe: no se
/// guardó nada (la transacción se deshizo) y la autorización no vale otra
/// vez. Un rechazo de validación anterior al consumo no usa esta excepción y
/// deja la autorización sin gastar.
class AuthorizedChangeNotSaved implements Exception {
  AuthorizedChangeNotSaved(this.cause);

  /// El error original, para el registro técnico.
  final Object cause;

  @override
  String toString() =>
      'No se guardó el cambio. La confirmación con el PIN ya se usó: '
      'vuelva a intentarlo y confirme otra vez con el PIN.';
}

/// Una aplicación con fecha pasada pide más de lo que la persona tenía ese
/// día y no se usó después (D-03, precisión de RN-25).
class HistoricalStockException extends BusinessRuleException {
  HistoricalStockException({
    required this.productId,
    required this.day,
    required this.heldBase,
    required this.availableBase,
    required this.requestedBase,
    required String message,
  }) : super(message);

  final int productId;

  /// Día local efectivo, `aaaa-mm-dd`.
  final String day;
  final int heldBase;
  final int availableBase;
  final int requestedBase;
}

class CampaignConflictException extends BusinessRuleException {
  CampaignConflictException(this.activeCampaignId, this.activeCampaignName)
    : super(
        'Está activa $activeCampaignName. Cierre esa campaña antes de activar otra.',
      );
  final int activeCampaignId;
  final String activeCampaignName;
}

/// Activar una sucesora que todavía no empezó cerraría la campaña actual antes
/// de tiempo: el día de hoy quedaría dentro de una campaña cerrada y sin
/// campaña operable (#125).
class CampaignActivationNotYetException extends BusinessRuleException {
  CampaignActivationNotYetException({
    required this.campaignName,
    required this.activeCampaignName,
    required this.activableFromDay,
  }) : super(
         '«$campaignName» empieza el ${displayDay(activableFromDay)}, después '
         'de hoy. Mientras «$activeCampaignName» esté activa no se puede '
         'activar cerrándola: el día de hoy quedaría dentro de una campaña '
         'cerrada. Se podrá activar desde el ${displayDay(activableFromDay)}; '
         'hasta entonces queda planificada.',
       );
  final String campaignName;
  final String activeCampaignName;

  /// Día local `aaaa-mm-dd` desde el que se admite la activación.
  final String activableFromDay;
}

/// Por qué la fecha efectiva de una operación no permite registrarla en la
/// campaña del borrador (RN-15, RN-16, RF-03).
enum CampaignDateProblem {
  /// Ninguna campaña contiene la fecha.
  none,

  /// Más de una campaña contiene la fecha: calendario solapado heredado.
  ambiguous,

  /// La fecha es de una campaña cerrada (Cap. III §3.11.13: requiere
  /// revisión). Su registro asociado está pendiente de decisión: D-F04-C1.
  closed,

  /// La fecha es de una campaña planificada, todavía no activa.
  planned,

  /// La fecha es posterior a hoy: una compra o aplicación ya realizada no
  /// puede tener una fecha futura (#121).
  future,
}

/// La operación no se registra: su fecha efectiva no clasifica en la campaña
/// activa. Nunca se asigna a otra campaña en silencio.
class CampaignDateException extends BusinessRuleException {
  CampaignDateException(this.problem, super.message);
  final CampaignDateProblem problem;
}

/// Un cambio del calendario de campañas solaparía períodos o dejaría
/// operaciones fuera del período de su campaña. No se aplica nada.
class CampaignCalendarException extends BusinessRuleException {
  CampaignCalendarException(super.message);
}

/// Se lanza cuando la modalidad propia (PERSONAL) no admite la operación.
class PersonalModeRestrictionException extends BusinessRuleException {
  PersonalModeRestrictionException(super.message);
}

/// Rechazo de un pago de cuenta personal al titular (decisión del autor del
/// 2026-11-12, que revisa el criterio Q-2/C-12).
const ownerAccountPaymentRejectedMessage =
    'El titular no tiene cuenta por cobrar: su consumo y sus costos son '
    'propios, no una deuda. No se registra un pago a su cuenta. Sus compras '
    'y pagos a proveedores se registran como siempre.';
