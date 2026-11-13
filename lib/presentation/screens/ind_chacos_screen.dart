// Modo individual — pestaña «Chacos» (láminas I-40 a I-43).
//
// Esqueleto de la base común (orquestador, 2026-11-13). Propietaria: sesión C
// (`_wt/IND-C`), que implementa la lista, el detalle, los costos y los
// estados vacíos reutilizando los cálculos existentes.
import 'package:flutter/material.dart';

import '../widgets/rdm_c_page.dart';

class ChacosScreen extends StatelessWidget {
  const ChacosScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const RdmCPage(title: 'Chacos', child: SizedBox.shrink());
}
