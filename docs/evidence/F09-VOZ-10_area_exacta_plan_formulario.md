# F09-VOZ-10 — Área exacta del plan en el formulario «Aplicar este plan»

- **Origen:** Live. **Fecha real:** 2026-10-17 (America/La_Paz).
- **Base:** Mobile `main` `ec69ae81a6e1168dfb4dd8d7b8a7181f1da1fcd2` (#110, #112 y #111 integrados; CI 39063721692 SUCCESS).
- **Rama:** `fix/f09-area-exacta-plan`. **Commits:**
  - `dcebd8a`: sólo la prueba; en ese commit falla;
  - `fdb6f3e`: la corrección. Es el commit verificado.
- **Entorno:** pruebas de **host** (Windows 11, Flutter 3.47.2). **No es una prueba DEVICE.**
- **Trazabilidad:** RF-28, RF-29, CU-16, INT-07 y DAT-17; MOB #15 y #16. GATE-F09 (#17) sigue Pending.
- **Decisión que se cumple:** «Precisión de área» (2026-10-17, por delegación). La voz conserva el `area_m2` exacto del plan. El formulario se corrige para que cargar y confirmar sin editar no cambie el área. No se modifica globalmente el formato de dinero, dosis ni cantidades.
- **Antecedente:** el límite declarado en `F09-VOZ-09_aplicar_plan_pendiente.md` §4 («Área del plan»). Allí queda una nota fechada; su texto se conserva.

## 1. Qué fallaba

Sobre `ec69ae8`, en `lib/presentation/screens/application_form_screen.dart`:

| Punto | Antes | Efecto con 10001 m² |
|---|---|---|
| Carga del plan (`_load`) | `formatForInput(area_m2 / 10000)`, 3 decimales | Mostraba «1» ha y guardaba **10000 m²** |
| Área tomada del chaco (`selectFarm`) | `formatForInput(hectáreas, maxDecimals: 2)` | Volver a elegir el chaco de 10001 m² mostraba «1» ha y guardaba 10000. Con 12345 m² mostraba «1,23» y guardaba 12300 |
| Teórica (`theoretical`) | `(ha × dosis × 1000).round()` en coma flotante | Con el área perdida, 5000 en vez de 5001. Aun con el área exacta, la coma flotante se aparta del redondeo mitad hacia arriba: 1,2345 ha × 5 L/ha dio **6172** en vez de 6173 |
| Doble toque de «Confirmar aplicación» | `submit` no miraba `saving` | El segundo toque intentaba otra escritura. El repositorio la rechazaba («Este plan ya fue aplicado…»), así que había una sola aplicación, pero se mostraba ese error |

La voz ya usaba el entero: `toDomain()` lleva `area.value` y `divideRoundedHalfUp(área × dosis, 10000)`. **La voz no se cambia.**

## 2. Corrección (`fdb6f3e`)

Un único archivo de `lib`, `application_form_screen.dart`:
- **`_areaInput(m²)`**, un helper local: `formatForInput(m² / 10000, maxDecimals: 4)`.
  - Un entero de m² tiene a lo sumo cuatro decimales en hectáreas, así que el texto es exacto: 10001 m² se muestra «1,0001» y se relee 10001.
  - Lo usan la carga del plan y el área del chaco.
  - Es la misma convención que ya usan las pantallas de voz (M-1, `voice_application_draft_screen.dart` y `voice_plan_draft_screen.dart`).
  - La persona ve lo que se guardará; no hay un área oculta distinta de la visible.
- **`_areaM2`** relee el campo en m². Lo usan las líneas, la aplicación y la teórica.
- **`theoretical`** se calcula en enteros, `divideRoundedHalfUp(_areaM2 × dosis_base, 10000)`.
  - Es la regla de la cantidad requerida del plan (`addPlanMulti`) y la de la voz.
  - La dosis es `tryParseBase`, la misma que se guarda en `dose_base_per_ha`.
- **`submit`** sale si `saving` ya está activo.

**Sin cambios en:**
- `formatForInput`, `numeric_input.dart` ni el formato de dinero, dosis o cantidades;
- la voz;
- `agro_repository.dart` ni los archivos de B (sincronización y campañas);
- el protocolo del ensayo.

No hay migración.

## 3. Prueba nueva: `test/plan_application_area_precision_test.dart`

Cada caso usa **dos bases sembradas igual**. En las dos hay:
- un chaco «Impar» de 10001 m²;
- stock de Glifosato y Bellator;
- un plan pendiente de **10001 m²** con Glifosato a 5 L/ha y Bellator a 1,5 L/ha.

Las cantidades requeridas son 5001 y 1500.

Los dos recorridos son reales:
- **El formulario:** el widget `ApplicationFormScreen(planId: …)`, como lo abre «Aplicar este plan». Se escribe en los campos y se toca «Confirmar aplicación».
- **La voz:** el intérprete, `VoiceDraftController` y `VoiceDraftGateway.confirmApplication`:
  - «aplicar la planificación del chaco Impar»;
  - se elige el plan;
  - «de Bellator en realidad usamos dos litros».

**Misma cantidad real:** Glifosato sin tocar (5001) y Bellator 2 L.

**Comparación:** se vuelcan **todas las tablas** de las dos bases (`dumpTables`) y deben tener el mismo conjunto de tablas y filas iguales. Sólo se descuenta lo que legítimamente difiere:
- `*_at`;
- `movement_date` y `transaction_date`, que son el instante de la aplicación: la voz usa su reloj y el formulario `DateTime.now()`;
- UUID;
- el identificador de operación.

Las fechas sembradas, como las de compra y de lote, sí se comparan.

| Caso | Qué comprueba |
|---|---|
| «plan de 10001 m²: formulario y voz guardan el área y la teórica exactas» | Campo «1,0001». `treated_area_m2` = 10001 en la aplicación y en las dos líneas. Teóricas 5001 y 1500, reales 5001 y 2000, `plan_id`. Las tablas son iguales a las de la voz |
| «el área editada a mano se guarda tal cual en los dos recorridos» | Edición explícita: «1,2345» en el formulario y 12345 m² a mano en la voz. Se guardan 12345, con teóricas 6173 y 1852 (mitad hacia arriba) y las reales sin cambio. Las tablas son iguales |
| «volver a elegir el chaco toma su área exacta, no con dos decimales» | Con el plan cargado, elegir el chaco de 10001 m² deja «1,0001» y guarda 10001 |
| «doble confirmación: una aplicación, igual que la voz» | Dos toques en el formulario y dos `confirm()` en la voz: una sola aplicación, sin aviso de error y tablas iguales |

**El código anterior falla.** El formulario de `ec69ae8` se repuso sobre el árbol de trabajo, se ejecutó la prueba final y luego se restauró la corrección. Lo mismo se obtiene ejecutando la prueba en `dcebd8a`. Resultado: **4 fallan**:
- `Expected: '1,0001'` / `Actual: '1'` (plan);
- `Expected: [6173, 1852]` / `Actual: [6172, 1852]` (edición);
- `Expected: '1,0001'` / `Actual: '1'` (chaco);
- `Found 1 widget with type "SnackBar"` (doble toque).

En una variante sin la comprobación del texto, el primer caso falla con `Expected: <10001>` / `Actual: <10000>` en `treated_area_m2`.

**Por qué no basta la prueba anterior.** La prueba de equivalencia de F09-VOZ-09 («mismo resultado que el formulario abierto desde «Aplicar este plan»») usa 10000 m² y reproduce a mano lo que arma el formulario, sin abrirlo. La M-1 de F09-VOZ-07 cubre la pantalla de voz con un chaco de 12345 m². Ninguna de las dos sustituye este caso, y las dos siguen igual.

## 4. Resultados sobre `fdb6f3e`

| Comando | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 (253 archivos, 0 cambiados) |
| `flutter analyze lib test` | `No issues found!` |
| `flutter test test/plan_application_area_precision_test.dart` | 4 pasan |
| `flutter test` (suite completa) | **1451 pasan, 2 omitidas, 0 fallos** |

La CI del HEAD del PR se anota en el PR.

## 5. Límites

- **Sin prueba en el teléfono.** El dictado real lo hace sólo A en el POCO, con una persona (V15–V19). Esta corrección cambia el binario del ensayo, así que el SHA del ensayo tiene que incluirla.
- **El área tecleada con más de cuatro decimales de hectárea** se redondea al m², como antes.
- **La teórica de una dosis tecleada con más de tres decimales** usa ahora la dosis redondeada que se guarda (`dose_base_per_ha`), y no el valor tecleado sin redondear.
- **Aplicación libre:** también la cubre el cambio, porque el área del chaco y la teórica son las mismas funciones. Un chaco de 12345 m² se precarga «1,2345» en vez de «1,23».
- **No se cambiaron** los CSV ni los registros de mediciones anteriores.
