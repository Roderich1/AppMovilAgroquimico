# Rediseño móvil: segunda ronda de correcciones (revisión del autor del 2026-11-12)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-12 (noche; en UTC, ya 2026-11-13) |
| Rama | `feat/rediseno-movil` (`_wt/RDM-MOB`), local, sin push |
| Base | `77deb95` (código instalado antes: `fc12123`) |
| Código final | **`b5df71d`** |
| Organización | `docs/rediseno/RONDA2_CORRECCIONES.md`: sesiones A (Compra), B (Almacén) y C (Personas) en `_wt/RDM2-A/B/C`; el orquestador se encargó de Inicio y Sindicato, de la integración y del emulador |
| APK instalada | `.rdm` «AC RDM», profile x86_64, compilada con el árbol limpio en `b5df71d`. SHA-256 **`6aeef0d5dec029d89900dd584235d1007c65208c3a9315dcbe17fa31296c73c1`**, igual en el archivo y en el `base.apk` del dispositivo |
| Dispositivo | `emulator-5556` (AVD `RDM_Pixel8`). **No** es un teléfono físico |

## Correcciones por pantalla

| Pantalla | Qué cambió | Commits |
|---|---|---|
| **Personas: pago al titular** | El repositorio rechaza el pago o adelanto de cuenta personal al titular vigente o a quien lo era ese día. Mensaje: «El titular no tiene cuenta por cobrar…». Se quitó del menú de la tarjeta propia, de la hoja de pago y del detalle. En inventario propio nadie recibe pagos de cuenta. Los asientos históricos se siguen mostrando como registro | `3fdd345` |
| **Personas: buscador** | Un solo buscador para Personas y Cuentas. Cada palabra cuenta en cualquier orden, sin distinguir mayúsculas ni tildes, con los espacios normalizados y la ñ conservada. Filtra también al titular y muestra «Ninguna persona coincide con «…».» | `40c6353` |
| **Inicio y Sindicato** | «Sindicato», en Inicio, abre la misma pantalla que la pestaña; entrar no envía ni consulta nada. Tres operaciones: «Enviar pendientes» (sólo si hay algo que enviar o que atender), «Actualizar» (consulta de convocatorias, siempre disponible) y «Ver estado de los envíos». «Envíos» (antes «Sincronización») queda como pantalla secundaria, sin repetir el menú y sin resumir todo como «sólo totales propios». Inicio muestra «Campaña activa: …» y «Cifras de todas las campañas» antes de la cifra | `9c21d06` |
| **Compra: hoja de producto** | Se ve la página real de Compra detrás, con un velo semitransparente (sin desenfoque). El fondo no se puede tocar, enfocar ni leer con lector de pantalla. Es el mismo borrador. La hoja se ajusta al teclado y a la letra | `da43854` |
| **Compra y lotes** | «Vencimiento (opcional)» siempre a la vista. «Lote del fabricante (opcional)» en «Más datos del envase». Nunca se genera un número. Sin «sin número de lote» en los resúmenes | `3ea2191`, `fb5de1c` |
| **Almacén: detalle** | «Hay ahora» y qué parte vence (cantidad y fecha). Debajo: «Quién lo tiene» («Usó X de Y»); «Planes pendientes» sólo si hay plan, con «Quedarían / Faltarían si se aplican los planes»; cinco movimientos y «Ver todo el historial»; y en «Más datos», lotes en tarjetas, valor «a costo de compra · no es una deuda» y avisos. Sin «Lote #» ni IDs internos. Mismas cifras | `a31a285` |
| **Personas: Cuentas y Costos** | Dos áreas y una sola lista. `/liquidacion` muestra la misma pantalla; los respaldos están en Ajustes › Respaldos. Costos por chaco, hectárea y producto, con «Exportar · Excel o PDF» | `ef01e72` |
| **Detalles de cuenta** | «Estado de cuenta» (otras personas) y «Movimientos propios» (titular) comparten estructura: cabecera con cifra y Exportar, Período, resumen y movimientos. El titular no tiene deuda ni «Registrar pago» | `ef01e72` |
| **PDF «Estado de cuenta»** | A4 apaisado, sin «…»: los textos se parten en líneas y las cabeceras se repiten en cada página. Antes había 209–210 cortes; ahora 0 | `b239afc` |

## Pruebas automatizadas (arnés con datos sintéticos; no es un recorrido)

| Ejecución | Comando | Resultado |
|---|---|---|
| Suite completa sobre `9404438` | `flutter test --no-pub --concurrency=4` | 3122 pasan, 3 omitidas, **3 fallan**. Las tres venían de un cambio de ruta del orquestador («Registrar › Pago» a `/personas` y la pista más larga): ruta `/liquidacion` sin origen y dos filas del panel «+» al 200 %. Se revirtió (`b5df71d`) |
| **Suite completa sobre `b5df71d` (código final)** | `flutter test --no-pub --concurrency=4` | **3125 pasan, 3 omitidas, 0 fallan** (07:42) |
| Regresiones nuevas | `rdm2_a_hoja_compra`, `rdm2_b_almacen_detalle`, `rdm2_c_pago_titular`, `rdm2_c_buscador`, `rdm2_c_pdf_estado_cuenta`, `rdm2_c_personas_areas`, y cuatro casos nuevos en `rdm_c_union_screen` | Incluidas en la suite. La sesión C comprobó que `rdm2_c_pago_titular` y `rdm2_c_buscador` fallaban sobre el código base: 4 de 9 cada una |

Las intermitencias conocidas (`f08_prev_01`, `rdm_a_personas_pago` bajo carga, `f10_x01_pago_datos`, `e2_joint_purchase_screens`) no fallaron en esta ejecución. **No se declaran resueltas** por eso.

## Recorrido en el emulador (`emulator-5556`, APK `b5df71d`)

- **Actualización conservando los datos.** `adb install -r`: `firstInstallTime` sigue en 2026-11-12 13:11:32. Las filas de las 45 tablas son iguales antes de instalar, después de abrir la app y tras el recorrido (`conteos_antes_instalar.txt`, `conteos_tras_recorrido.txt`). Esquema 19.
- **Sindicato no envía al entrar.** El registro de la compuerta del túnel (sólo método, ruta y estado) tuvo 0 peticiones al abrir Sindicato desde Inicio y 0 al abrir «Ver estado de los envíos».
- **Pago al titular.** El menú ⋮ de Rosa Vargas (titular) ofrece sólo «Ver movimientos propios» y «Exportar movimientos propios» (`despues/05`). Juan Mamani conserva «Registrar pago» en su tarjeta.
- **Buscador.**
  - «ro» → sólo Rosa;
  - «VARGAS  rosa» (mayúsculas, espacio doble, orden inverso) → Rosa;
  - «mamani juan» → Juan;
  - «xyz» → «Ninguna persona coincide con «xyz».».

  Capturas `despues/071–074`. Las tildes no se pueden teclear con `adb input text`; las cubre `rdm2_c_buscador`.
- **Compra.**
  - La hoja muestra la página de Compra atenuada detrás (`despues/11`).
  - Con el teclado abierto, «Listo» y «Añadir otro» quedan a la vista (`12`).
  - «Más datos del envase» contiene «Lote del fabricante (opcional)» (`13`).
  - Lo escrito se conserva al ocultar el teclado.
  - La compra se descartó sin guardar.
- **Almacén.** Las cifras son las mismas que en la captura del autor: 3 L, «1 L vence el 11/12/2026», Juan 2 L, Rosa 1 L, previsto 1,5 L (`10`).
- **Letra 130 % y 200 %.** Inicio, Sindicato, Personas y detalle de producto (`20–23_*_x13|x20`). Se restauró `font_scale` a 1.0.
- **Antes.** `O/antes/` (código `fc12123`).

Capturas del arnés antes y después, también a 900 dp de ancho: `A/`, `B/` y `C/` (cada una con su README). PDF: `C/pdf/{antes,despues}/`.

## Datos previos incompatibles

Hay un asiento de pago al titular: asiento 5, Rosa Vargas, 22,00 Bs, del 2026-11-12, imputado a su cargo propio. Se registró con el menú Q-2 durante la revisión del autor. No se borró ni se reclasificó. Detalle en `O/asientos_titular_emulador.md`.

## Decisiones abiertas para el autor

1. **Asiento 5 (22,00 Bs).** ¿Se revierte con un motivo o se deja como registro?
2. **Almacén.** «Quedarían si se aplican los planes» y «Valor a costo de compra» incluyen lotes ya vencidos (cálculo actual, sin cambios). ¿Deben excluirlos?
3. **Personas.** La cabecera dice «Le deben · todas las campañas» y la lista empieza filtrada por la campaña activa, como Cuentas hasta ahora (D-04 H-12). Ambos alcances están rotulados. ¿Se mantiene así?
4. **Modo propio (#26).** Con la regla nueva nadie registra pagos de cuenta en inventario propio, porque no hay cuentas por cobrar.
5. **Contrato `D04_E15_…` §7.** Falta anotar que el autor revisó Q-2/C-12 el 2026-11-12. No se editó `docs/architecture`.

## Limitaciones y pendientes

- Nada se probó en un teléfono físico, ni con lector de pantalla real, ni la voz con una persona.
- La revisión funcional de Sindicato junto con la Web sigue pendiente; aquí sólo cambian la navegación y la presentación. «Enviar pendientes» y «Actualizar» no se pulsaron en el emulador, porque requieren verificar el acceso en línea con la cuenta de revisión y habrían escrito en el servidor.
- La tarjeta del titular en Cuentas conserva términos técnicos («costo FIFO», «asientos», «créditos por reversión»). El detalle ya los relega, pero la tarjeta de la lista no se simplificó en esta ronda.
- Componentes candidatos a `agro_ui.dart` (`LotCard`, `ExpiryLine`, buscador) siguen en archivos propios de cada sesión.
- La «entrada i de n» de los lotes se renumera si una entrada del mismo día se agota.
- El túnel temporal sigue abierto para la revisión del autor; la APK está atada a él.

## Guía para la siguiente revisión del autor

1. **Inicio:** «Campaña activa: …», la pastilla «Cifras de todas las campañas», y «Sindicato» abre la pestaña Sindicato.
2. **Sindicato:** «Nada por enviar», «Actualizar» y «Ver estado de los envíos» → «Envíos».
3. **Personas › Cuentas:**
   - el ⋮ de la titular no tiene «Registrar pago»;
   - prueba el buscador con mayúsculas, tildes y el orden de las palabras.
4. **Personas › Costos:** chacos, hectáreas y productos, y «Exportar · Excel o PDF».
5. **Detalles:** «Ver cuenta» de Juan frente a «Ver movimientos propios» de Rosa.
6. **Exportar el estado de cuenta en PDF** y revisar las columnas.
7. **Registrar compra → Añadir producto:** página detrás, «Más datos del envase». Descarta al salir.
8. **Almacén → Herbicida sin red:** vencimiento por cantidad, planes, «Ver todo el historial» y «Más datos › Lotes».
