// Decisiones de texto del autor (2026-11-12, revisión del rediseño): fijan
// los rótulos para que no vuelvan atrás sin una decisión nueva. Sólo textos:
// no cambian permisos ni la regla entre persona y chaco.
import 'package:agroquimicos/presentation/screens/application_form_screen.dart'
    show applicationPersonLabel;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'aplicación: el selector de persona pregunta de quién son los '
    'productos (la persona cuyas existencias se usan y a quien se carga)',
    () {
      expect(applicationPersonLabel, '¿De quién son los productos?');
    },
  );
}
