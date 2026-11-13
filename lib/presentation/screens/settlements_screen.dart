import 'package:flutter/material.dart';

import '../widgets/rdm2_c_accounts.dart';
import 'persons_screen.dart';

/// `/liquidacion` (ronda 2, sesión C): ya no es una segunda lista de las
/// mismas personas. Muestra Personas en su área «Cuentas», con el mismo
/// filtro de campaña, búsqueda, tarjetas, pagos, estado de cuenta, costos (en
/// «Costos») y exportación. Los respaldos, que esta pantalla ofrecía en su
/// cabecera, están en Ajustes › Respaldos (`/respaldo-remoto`).
///
/// Se conserva la ruta para los accesos que ya la usan («Registrar › Pago»,
/// enlaces guardados); el orquestador puede redirigirla a `/personas`.
class SettlementsScreen extends StatelessWidget {
  const SettlementsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const PersonsScreen(initialArea: PersonsArea.accounts);
}
