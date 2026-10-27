# Bloque 1 de la revisión integral — Nueva compra sin elecciones ocultas

- **Fecha real:** 2026-10-27 (America/La_Paz). Sesión A, por encargo de Roderich del 2026-10-26 (frente 2). Rama `fix/compra-sin-elecciones-ocultas` sobre `main` `a68285c`.
- **Trazabilidad:** CU-06 (compra), RF-04/RF-05 (asignación por persona), RN-10, RN-16; INT-01. Issue MOB #37.
- **Motivo:** en X01 y X02 las existencias quedaron asignadas a «Familiar Demo» y en X02 faltó el segundo producto (dato de la base, no intención de la persona); el formulario autoseleccionaba el producto restante (B-08) y exigía elegir persona y reteclear la cantidad por producto (B-21).

## 1. Commits

| SHA | Qué |
|---|---|
| `0c912d5` | Selector de producto por línea sin autoselección; «¿Para quién es?» con «Toda para una persona» (cantidad derivada) o «Repartir entre varias»; titular rotulado por el vínculo; resumen con destinatario; «Paga el titular»; mensajes que nombran el producto; formato en el campo; proveedor único no marca cambios |
| `c7f9404` | `test/f10_compra_destinatario_explicito_test.dart` (nuevo) y 8 pruebas adaptadas sólo en texto |
| `b848069` | Revisión cruzada: persona repetida en el reparto rechazada; cambio de opción limpia la anterior; mensajes en usted |

`agro_repository.dart`, el contrato de `confirmPurchase`, la regla del pagador y `ProviderPaymentFields` no cambian.

## 2. Pruebas de host

- Casos (a) sin autoselección con dos productos, (f) Atrás sin diálogo con proveedor único y (g) «1.5»/«1,500» con mensaje de formato **fallan sobre `a68285c`** y pasan con la corrección; (b)–(e) y (h) describen el diseño nuevo (cantidad derivada y asignación completa en el repositorio; reparto exacto; persona repetida; sin destinatario no continúa; propio sin grupo; cambio de opción limpio).
- `flutter test test/f10_compra_destinatario_explicito_test.dart` → `00:24 +9: All tests passed!`; `f10_x01_regresiones_test` +2; `f10_x01_pago_revision_test` +3; `personal_mode_flows_test` +15; `ui_polish_test` +18 (salidas literales en el informe de sesión `salida_pruebas_v2.txt`).
- Suite completa en la rama (`b848069`, bajo otra suite en paralelo): 1 852 pasan, 3 omitidas, **1 fallo** en `operation_mode_onboarding_test` («propio → compartido con historial…», `database_closed`), prueba ajena a esta rama: aislada pasa en `main` 3/3 y en esta rama alterna (1 fallo, 1 pase) con la máquina cargada. Se declara inestable bajo carga, no regresión.
- `dart format` sin cambios; `flutter analyze` «No issues found!». Commits sin trailers.
- **Revisión cruzada:** NO LISTO en primera lectura por dos ajustes del encargo literal (persona repetida; limpiar al cambiar de opción), incluidos en `b848069`; registro unificado a usted en los mensajes nuevos.

## 3. Comprobación en EMULADOR (integración local de las cuatro ramas)

Ver `F10_BLOQUE1_INTEGRACION_EMULADOR.md` (misma fecha): en COMPARTIDA, la línea 2 apareció como «Seleccione producto» (sin autoselección); «Toda para una persona» → «Recibe toda la cantidad comprada: 2 L.» y cabecera «Para: Titular» sin teclear; «Repartir entre varias» con Titular 0,3 L y Familiar Demo 0,2 L; un importe mal escrito mostró «Escriba el número como 1.500,25…» y «Revise las cantidades repartidas de Bellator.»; paso 2 «Glifosato Demo · 2 L · 20,00 Bs · Para: Titular», «Bellator · 0,5 L · 5,00 Bs · Repartida: Titular 0,3 L · Familiar Demo 0,2 L», «Paga el titular: Titular»; base: asignaciones (1→Titular 2 000; 2→Titular 300; 2→Familiar Demo 200), pago 25,00 Bs `UNSPECIFIED` por el Titular. En PROPIA: sin pregunta, «Para el titular: Titular», asignación 1 000 al titular. Atrás con sólo el proveedor autoseleccionado cerró sin «¿Descartar cambios?».

## 4. Pasos y textos para la hoja del facilitador

- «Comprar 2 productos, todo para el titular, pagada» (compartida, desde Operaciones): antes 22 toques y 6 números; después 22 toques y 4 números (la decisión «Toda para una persona» sustituye reteclear la cantidad). Propio: 16 → 16.
- Textos nuevos: «¿Para quién es?» · «Toda para una persona» · «Repartir entre varias» · «Elija una opción para indicar a quién va este producto.» · «Recibe toda la cantidad comprada: N L.» · «Pendiente de destinatario» · «Para: X» · «Repartida: X n L · Y m L» · «Paga el titular: X» · «La misma persona aparece dos veces en el reparto de P.» · «Indique para quién es P: toda para una persona o repartida entre varias.».

## 5. Límites

Sin teléfono físico (el POCO dejó de estar conectado el 2026-10-27 antes de esta comprobación); cuatro textos previos siguen en tú («Elige el proveedor.», «Agrega al menos un producto.», «Indica si pagaste toda esta compra.», «Elige una opción para poder confirmar.»): decisión de registro para Roderich.
