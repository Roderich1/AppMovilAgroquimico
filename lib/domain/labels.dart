/// Textos de usuario para los valores que la base guarda como literales.
///
/// Existe porque los mismos enums se traducían en unas pantallas y se mostraban
/// en crudo en otras (`PLANNED`, `THIRD_PARTY`, `PAYMENT`): el usuario objetivo
/// es un agricultor hispanohablante y esos literales no significan nada para él
/// (UIBUG-016). La regla vive en un solo sitio para que no vuelva a divergir.
library;

/// Rol de una persona: `ADMIN`, `FAMILY`, `THIRD_PARTY`.
String personRoleLabel(Object? role) => switch (role) {
  'ADMIN' => 'Administrador',
  'FAMILY' => 'Familiar',
  'THIRD_PARTY' => 'Tercero',
  _ => '$role',
};

/// Estado de una campaña: `ACTIVE`, `PLANNED`, `CLOSED`.
String campaignStatusLabel(Object? status) => switch (status) {
  'ACTIVE' => 'Activa',
  'PLANNED' => 'Planificada',
  'CLOSED' => 'Cerrada',
  _ => '$status',
};

/// Estado de una operación (compra, aplicación, transferencia).
String operationStatusLabel(Object? status) => switch (status) {
  'CONFIRMED' => 'Confirmada',
  'REVERSED' => 'Revertida',
  _ => '$status',
};

/// Origen del tipo de cambio de una compra (`ExchangeRateSource.code`).
String exchangeRateSourceLabel(Object? source) => switch (source) {
  'AGREED_WITH_SUPPLIER' => 'Acordado con el proveedor',
  'OFFICIAL_REFERENCE' => 'Referencia oficial',
  'MANUAL' => 'Escrito por la persona',
  'OTHER' => 'Otro',
  _ => '$source',
};

/// Tipo de asiento de `account_transactions`.
String transactionTypeLabel(Object? type) => switch (type) {
  'USAGE_CHARGE' => 'Cargo por consumo',
  'PURCHASE_ALLOCATION_CHARGE' => 'Cargo por compra',
  'PAYMENT' => 'Pago',
  'ADVANCE' => 'Adelanto',
  'CREDIT_ADJUSTMENT' => 'Crédito por reversión',
  _ => '$type',
};

/// Concepto de un movimiento de cuenta, ya legible.
///
/// `detailedStatement` compone `concept` con
/// `COALESCE(<productos>, <producto>, t.notes, t.type)`: cuando un pago no tiene
/// notas cae al último término y el `type` crudo (`PAYMENT`) acababa pintado
/// como título del movimiento. Aquí se traduce ese caso (UIBUG-016).
String conceptLabel(Object? concept) {
  final text = '$concept';
  final translated = transactionTypeLabel(text);
  return translated == text ? text : translated;
}

/// Aviso previo a confirmar una transferencia (D-07, RN-35; decisión del autor
/// del 2026-10-27). Transferir sólo mueve producto: no inserta ninguna fila en
/// `account_transactions`, tampoco cuando el destino es un tercero que paga
/// por compra (`BY_PURCHASE_ALLOCATION`). La frase es literal y vale igual con
/// uno o varios productos.
String transferNoDebtNotice(String recipient) =>
    'Esta transferencia entrega producto a $recipient, pero no genera una '
    'deuda.';

/// Rótulo breve del carácter de una transferencia en los historiales: es una
/// entrega de producto, no una venta ni un cargo.
const transferNoDebtLabel = 'Entrega sin deuda';
