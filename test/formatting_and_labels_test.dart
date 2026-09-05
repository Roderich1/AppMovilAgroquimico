// Grupo FORMAT_LOCALIZATION: UIBUG-016, 024, 026, 027, 056.
//
// La aplicación mezclaba convenios en la misma línea ("80.0 ha" junto a
// "20.160,00 Bs"), mostraba fechas ISO, cantidades crudas en gramos
// ("FIFO: #1: 600000") y literales del esquema sin traducir (PLANNED,
// THIRD_PARTY, PAYMENT). Todo eso se centraliza aquí para que no vuelva a
// divergir pantalla por pantalla.

import 'package:agroquimicos/domain/labels.dart';
import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/domain/text_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UIBUG-024 · superficies con convenio es-BO', () {
    test('entero sin decimales, decimal con coma', () {
      expect(formatHectares(800000), '80 ha');
      expect(formatHectares(1205000), '120,5 ha');
      expect(formatHectares(0), '0 ha');
    });

    test('la parte decimal usa coma, no punto', () {
      // En "9.999 ha" el punto es separador de MILES, que es correcto en es-BO;
      // lo que no debe aparecer nunca es un punto separando decimales.
      expect(formatHectares(125000), '12,5 ha');
      expect(formatHectares(1205000), '120,5 ha');
      expect(formatHectares(99995000), '9.999,5 ha');
    });

    test('agrupa los miles como el resto de la app', () {
      expect(formatHectares(99990000), '9.999 ha');
    });
  });

  group('UIBUG-027 · fechas localizadas', () {
    test('ISO -> dd/mm/aaaa', () {
      expect(formatDate('2026-01-25'), '25/01/2026');
      expect(formatDate('2025-07-01T10:30:00.000Z'), '01/07/2025');
    });

    test('un texto que no es fecha se devuelve intacto', () {
      expect(formatDate('sin fecha'), 'sin fecha');
      expect(formatDate(null), 'null');
    });
  });

  group('UIBUG-026 · detalle FIFO legible', () {
    test('convierte unidades base a la unidad del producto', () {
      // Antes se leía "FIFO: #1: 600000" (gramos, sin unidad ni formato).
      expect(formatFifoLots('#1: 600000', 'KG'), '#1 600 KG');
      expect(
        formatFifoLots('#1: 600000,#2: 25500', 'KG'),
        '#1 600 KG · #2 25,5 KG',
      );
    });

    test('sin datos lo dice', () {
      expect(formatFifoLots(null, 'KG'), 'sin detalle');
      expect(formatFifoLots('', 'KG'), 'sin detalle');
    });

    test('un formato inesperado se devuelve intacto, no rompe la pantalla', () {
      expect(formatFifoLots('otra cosa', 'KG'), 'otra cosa');
    });
  });

  group('UIBUG-016 · literales del esquema traducidos', () {
    test('roles', () {
      expect(personRoleLabel('ADMIN'), 'Administrador');
      expect(personRoleLabel('FAMILY'), 'Familiar');
      expect(personRoleLabel('THIRD_PARTY'), 'Tercero');
    });

    test('estados de campaña', () {
      expect(campaignStatusLabel('ACTIVE'), 'Activa');
      expect(campaignStatusLabel('PLANNED'), 'Planificada');
      expect(campaignStatusLabel('CLOSED'), 'Cerrada');
    });

    test('estados de operación', () {
      expect(operationStatusLabel('CONFIRMED'), 'Confirmada');
      expect(operationStatusLabel('REVERSED'), 'Revertida');
    });

    test('tipos de asiento', () {
      expect(transactionTypeLabel('PAYMENT'), 'Pago');
      expect(transactionTypeLabel('ADVANCE'), 'Adelanto');
      expect(transactionTypeLabel('USAGE_CHARGE'), 'Cargo por consumo');
      expect(
        transactionTypeLabel('PURCHASE_ALLOCATION_CHARGE'),
        'Cargo por compra',
      );
      expect(
        transactionTypeLabel('CREDIT_ADJUSTMENT'),
        'Crédito por reversión',
      );
    });

    test('el concepto de un pago sin notas ya no es "PAYMENT"', () {
      // `detailedStatement` compone concept con COALESCE(..., t.notes, t.type):
      // un pago sin notas caía al type crudo y se pintaba como título.
      expect(conceptLabel('PAYMENT'), 'Pago');
      // Un concepto real (nombre de producto) se respeta tal cual.
      expect(conceptLabel('Glifosato 68 SG'), 'Glifosato 68 SG');
    });

    test('un valor desconocido no se pierde', () {
      expect(personRoleLabel('OTRO'), 'OTRO');
      expect(campaignStatusLabel(null), 'null');
    });
  });

  group('UIBUG-019 · búsqueda insensible a tildes', () {
    test('encuentra con y sin tildes', () {
      expect(matchesSearch('Hacienda Santa María', 'maria'), isTrue);
      expect(matchesSearch('María Fernanda', 'MARIA'), isTrue);
      expect(matchesSearch('José Luis Álvarez', 'jose'), isTrue);
      expect(matchesSearch('José Luis Álvarez', 'alvarez'), isTrue);
    });

    test('la ñ se conserva: es una letra, no una n con tilde', () {
      expect(normalizeForSearch('Áñez'), 'añez');
      expect(matchesSearch('Ana Áñez', 'añez'), isTrue);
      expect(
        matchesSearch('Ana Áñez', 'anez'),
        isFalse,
        reason: 'ñ y n son letras distintas en español',
      );
    });

    test('no encuentra lo que no está', () {
      expect(matchesSearch('Glifosato 48 SL', 'urea'), isFalse);
    });

    test('una búsqueda vacía no filtra nada', () {
      expect(matchesSearch('cualquier cosa', ''), isTrue);
    });
  });

  group('UIBUG-056 · decimales estables en la misma columna', () {
    test('formatQuantity mantiene el convenio es-BO', () {
      expect(formatQuantity(174250, 'L'), '174,25 L');
      expect(formatQuantity(15000000, 'KG'), '15.000 KG');
      expect(formatQuantity(125, 'KG'), '0,125 KG');
    });
  });

  group('UIBUG-025 · resúmenes formateados en presentación, no en SQL', () {
    test('convierte los datos crudos al convenio de la app', () {
      // Antes SQL emitía "Urea 25.0 KG" y "Fosfato Diamónico 5000.0 KG".
      expect(formatItemsSummary('Urea|25000|KG'), 'Urea 25 KG');
      expect(
        formatItemsSummary('Fosfato Diamónico|5000000|KG'),
        'Fosfato Diamónico 5.000 KG',
      );
      expect(
        formatItemsSummary('Glifosato 68 SG|30000|KG;Mancozeb 80|50500|KG'),
        'Glifosato 68 SG 30 KG · Mancozeb 80 50,5 KG',
      );
    });

    test('sin datos devuelve vacío y un formato inesperado no rompe', () {
      expect(formatItemsSummary(null), '');
      expect(formatItemsSummary(''), '');
      expect(formatItemsSummary('texto suelto'), 'texto suelto');
    });
  });
}
