// #82: las fechas mostradas usaban el día UTC. Una fecha civil (aaaa-mm-dd)
// se muestra tal cual; un instante, en el día local del teléfono.
//
// Varias pruebas sólo discriminan fuera de UTC. La CI corre en UTC y además
// repite este archivo con TZ=America/La_Paz; el centinela hace fallar ese paso
// si la zona no se aplicó.
import 'dart:io';

import 'package:agroquimicos/domain/money.dart';
import 'package:agroquimicos/domain/reports/report_table.dart';
import 'package:flutter_test/flutter_test.dart';

/// Desfase local de la zona del piloto (Bolivia, sin horario de verano).
const _laPaz = Duration(hours: -4);

bool get _runningInLaPaz => DateTime(2026, 10, 15, 12).timeZoneOffset == _laPaz;

void main() {
  test('centinela: el paso regional de la CI corre en America/La_Paz', () {
    final expected = Platform.environment['AGRO_TZ_REGRESSION'];
    if (expected == null) {
      markTestSkipped('sólo en el paso regional de la CI');
      return;
    }
    expect(expected, 'America/La_Paz');
    expect(DateTime(2026, 10, 15, 12).timeZoneOffset, _laPaz);
  });

  test('una fecha civil nunca se desplaza, en ninguna zona', () {
    expect(formatDate('2026-10-15'), '15/10/2026');
    expect(formatDate('2026-01-01'), '01/01/2026');
    expect(formatDate('2025-12-31'), '31/12/2025');
  });

  test('un instante de la noche se muestra en su día local', () {
    // Lo que guarda la app para algo hecho a las 21:38 locales.
    final evening = DateTime(2026, 10, 15, 21, 38).toUtc().toIso8601String();
    expect(formatDate(evening), '15/10/2026');
    // Y justo después de la medianoche local.
    final early = DateTime(2026, 10, 16, 0, 5).toUtc().toIso8601String();
    expect(formatDate(early), '16/10/2026');
  });

  test(
    'en Bolivia: los instantes guardados en el POCO se muestran el 15/10',
    () {
      // Valores reales del E2E de D3 (2026-10-15 ~22:00 -04): creación de la
      // campaña y ACK de Central. Con el formato UTC salían el 16/10.
      expect(formatDate('2026-10-16T01:38:55.420895Z'), '15/10/2026');
      expect(formatDate('2026-10-16T02:01:14.271Z'), '15/10/2026');
      // A las 04:00Z ya es medianoche en Bolivia.
      expect(formatDate('2026-10-16T04:00:00.000Z'), '16/10/2026');
    },
    skip: _runningInLaPaz ? false : 'sólo discrimina en America/La_Paz',
  );

  test('las exportaciones CSV/PDF usan la misma regla', () {
    final evening = DateTime(2026, 3, 1, 22).toUtc().toIso8601String();
    expect(ReportDate(evening).csvText, '01/03/2026');
    expect(ReportDate(evening).displayText, '01/03/2026');
    expect(const ReportDate('2026-03-01').csvText, '01/03/2026');
  });

  test('un texto que no es fecha se devuelve intacto', () {
    expect(formatDate('sin fecha'), 'sin fecha');
    expect(formatDate('2026-13-45'), '2026-13-45');
  });
}
