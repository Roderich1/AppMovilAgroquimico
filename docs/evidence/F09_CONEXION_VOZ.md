# F09 — Conexión de la voz con la app (rutas, Operaciones y formularios)

- **Origen:** Live. **Fecha real:** 2026-10-17 (America/La_Paz).
- **Base:** Mobile `main` `a25c2162abf7756c184e77a6150f4e28659b15af` (pila F09 integrada: #99, #100, #101 y #104; F04 #102; #97 #103; #106; #107).
- **Rama:** `feat/f09-conexion-voz`. **Commit verificado:** `980918c9a3ab7635719ffc764cb8db1cecb4dbb8`.
- **Entorno:** pruebas de **host** (Windows 11, Flutter 3.47.2). **No es una prueba DEVICE.**
- **Trazabilidad:** RF-28, RF-29, CU-16, INT-07 y DAT-17; MOB #11, #14, #15 y #16. GATE-F09 (#17) sigue Pending.

> **Actualización del 2026-10-17 (C):** D-F09-4 se decidió después de este registro: sí se aplica un plan pendiente por voz. Lo entrega `docs/evidence/F09-VOZ-09_aplicar_plan_pendiente.md`. Lo que sigue se conserva tal como se verificó sobre su commit.

## 1. Qué se conectó

| Commit | Qué |
|---|---|
| `a544b08` | **Alineación con F04.** Las pantallas de voz usan las mismas lecturas que sus formularios: compra con `peopleAndContextFor(purchaseAllocation)`, planificación con `farmsAndContext` y aplicación con `peopleAndContextFor(applicator)`. **En propio no hay selector de persona:** la compra es del titular, y una persona dictada («todo para …») se ignora y se informa. El catálogo recuerda la modalidad con que se leyó; si cambia con la pantalla abierta (`operationModeProvider` y `modeChangedSince`), aparece `ModeChangedNotice` y no se puede confirmar |
| `fdbf55d` | **Commit aparte de conexión del shell** (`app.dart`, `app_shell.dart` y `operations_screen.dart`). Tarjeta «Registrar por voz» al final de Operaciones, para no mover las demás. Rutas dentro del `ShellRoute`, sin el FAB global en ellas |
| `d72353a` | «Dictar con voz» en los formularios de compra, planificación y aplicación; si el formulario tiene cambios, pregunta antes de descartarlos. No se ofrece en la aplicación de un plan (D-F09-4). Overrides opcionales en el arnés de F04 y pruebas de la conexión |
| `980918c` | De la voz al formulario manual: si hay un borrador empezado, pregunta, como Atrás (`PopScope`). Después descarta el borrador sin escribir y suelta el micrófono |

**Rutas:**

| Ruta | Pantalla |
|---|---|
| `/voz` | Entrada: compra, planificación o aplicación por voz |
| `/compras/voz` | Borrador de compra; su formulario manual es `/compras/nueva` |
| `/planificacion/voz` | Borrador de planificación; su formulario es `/planificacion/nueva` |
| `/aplicaciones/voz` | Borrador de aplicación; su formulario es `/aplicaciones/nueva` |

**Lo que no hay por voz:**
- **transferencias** (ni en propio ni en compartido);
- pagos;
- consultas;
- aplicar un plan pendiente.

**La pantalla de captura sólo de texto del PR #8 no se expone como destino:** su «Usar este texto» no registra nada y los borradores la sustituyen. Su panel de escucha es el que usan los borradores.

## 2. Pruebas de la conexión (`test/voice_draft/voice_wiring_test.dart`, app real con el puerto de voz fake)

| Prueba | Comprueba |
|---|---|
| Operaciones → Registrar por voz → los tres borradores | La entrada abre compra, planificación y aplicación por voz; sin nada dictado, Atrás vuelve a la entrada |
| Sin FAB global en las pantallas de voz | `/compras/voz` sin `FloatingActionButton` |
| Formulario de compra → Dictar → borrador → formulario manual | Ida y vuelta entre las dos vías equivalentes, con el micrófono suelto |
| Propio | La compra es del titular (`voz-titular`) y no aparece el selector de persona. La persona dictada se ignora y se informa. Un cambio de modalidad muestra `mode-changed-notice` y deshabilita «Registrar» |
| Con un borrador dictado, pasar al formulario pregunta | El diálogo «¿Descartar el borrador?» aparece; después se abre el formulario, sin compra escrita y con el micrófono suelto |

## 3. Resultados sobre `980918c9a3ab7635719ffc764cb8db1cecb4dbb8`

| Comando | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | exit 0 (248 archivos) |
| `flutter analyze lib test` | `No issues found!` |
| `flutter test test/voice_draft/voice_wiring_test.dart` | 5 pasan |
| `flutter test` (suite completa) | **1402 pasan, 2 omitidas, 0 fallos** |

## 4. Qué no está probado

- **El reconocimiento real.** Todas las pruebas usan el puerto fake. Hace falta dictado real de una persona en el teléfono: el ensayo físico de `docs/evolution/features/F09_VOZ_ENSAYO_FISICO_PLAN.md`, con turno de A, y la validación de #12. Hasta entonces, el motor queda `NOT_MEASURED` en esta versión.
- **La navegación en el teléfono:** probada sólo en host.
- **La restauración con una pantalla de voz abierta:** cubierta sólo por el aviso de cambio de modalidad, no con una restauración real.

**Decisiones pendientes que acotan el alcance:**
- D-F09-2: sin «Crear nuevo»;
- D-F09-3: plan = área + dosis;
- D-F09-4: sin aplicar un plan por voz;
- D-F09-7: reconocedor del sistema con consentimiento.
