# F04-MODE-02 (#25): elección comprensible de la modalidad, consulta y cambio

Refs #25. Trazabilidad (Cap. III v1.5): RF-06, RNF-07; CU-05.

Misma rama, commits y entorno que [F04-MODE-03_flujos_modo_personal.md](F04-MODE-03_flujos_modo_personal.md):
- `feat/f04-modo-ui` sobre `main` `ce5678f`;
- commits `db0b10a` y `7ac7153`;
- 2026-10-17, Flutter 3.47.2;
- pruebas de host y de widgets, **sin dispositivo**.

## Qué existía y qué faltaba

Ya integrado con #78:
- la elección inicial de la modalidad en la pantalla del titular, tras activar;
- la pantalla Modo de uso (`/modo`, desde Operaciones), con bloqueo y confirmación.

Contrastado con los criterios de #25, faltaba:
- la explicación de cada modalidad («Varios responsables y transferencias» / «Sólo el titular registra»);
- decir qué bloquea y cómo resolverlo: sólo había conteos («1 persona(s) con existencias»);
- un mensaje de transición que dijera qué cambió;
- que la interfaz reflejara la modalidad vigente fuera de esa pantalla.

## Qué cambia

- **Un mismo texto para cada modalidad** (`operationModeExplanation`), en la elección inicial y en Modo de uso.
  - Compartido: «Varias personas (familiares o terceros) compran, aplican y transfieren productos; cada una tiene su inventario y su cuenta.»
  - Propio: «Sólo el titular compra, aplica y paga. No hay transferencias ni hay que elegir persona en los formularios.»
- **Elección inicial:** una ayuda dice que se puede cambiar después en Operaciones › Modo de uso, sin perder registros y sin conexión. El mensaje final dice qué modalidad quedó y dónde cambiarla.
- **Modo de uso:** muestra la vigente y su explicación, y qué significa cambiar a la otra, con «no borra ni reasigna registros y no necesita conexión».
- **Bloqueo** (SHARED → PERSONAL): nombra a las personas y dice cómo resolverlo.
  - existencias de «Hermana»: regístrelas en una aplicación o transfiéralas al titular;
  - planes abiertos en chacos de …: aplíquelos o cancélelos;
  - saldo de cuenta de …: registre el pago en Cuentas.

  Lo lee `OperationModeStore.describe`, que sólo lee. Si la situación cambia entre evaluar y escribir, se muestra la causa nueva.
- **Mensajes de transición:**
  - a propio: «Ahora usa inventario propio. Se ocultaron las transferencias y la elección de persona; el historial se conserva»;
  - a compartido: «Ya puede registrar responsables y transferencias; el historial sigue asociado al titular».
- **La interfaz refleja la vigente:** Operaciones muestra «Ahora: inventario propio/compartido» y oculta o muestra transferencias sin reiniciar (#26).

## Pruebas: `test/operation_mode_onboarding_test.dart` (nuevo, 3 casos)

Las tres usan un transporte HTTP que falla y cuenta las peticiones: **0 peticiones** en cada caso.

| Caso | Qué comprueba |
|---|---|
| Recién activado sin titular | Estado `activationPendingOwner` y ruta `/titular`. Se muestran la ayuda y las dos explicaciones. Se crea el titular eligiendo «Propio»: queda `PERSONAL` en la base y en la presentación, con mensaje de transición; Operaciones muestra «Ahora: inventario propio» y no ofrece Transferencias |
| Consulta posterior con existencias de la hermana | Modo de uso muestra la vigente y las dos explicaciones. Al intentar pasar a propio, el bloqueo nombra a «Hermana», dice cómo resolverlo y que no se borra nada; no pide confirmación; el volcado completo de la base es idéntico y la modalidad sigue `SHARED` |
| Propio → compartido con historial (compra y aplicación) | El diálogo dice que el historial sigue asociado al titular; tras confirmar, el mensaje de transición y la vigente cambian. Tablas de negocio idénticas, existencias por persona y producto idénticas, `operation_mode=SHARED`. Operaciones vuelve a ofrecer Transferencias |

Las mutaciones N9, N10 y N14 de [F04-MODE-03](F04-MODE-03_flujos_modo_personal.md) afectan a este flujo y se detectan.

## Contraste con los criterios de #25

| Criterio | Evidencia | Estado |
|---|---|---|
| Recién activado: elige entre propio y compartido con una explicación breve, y queda persistida | Caso 1; `f04_operation_mode_test` (persistencia tras reabrir) | Cumplido en host |
| De propio a compartido: el historial sigue con el titular y se habilitan responsables y transferencias | Caso 3 | Cumplido en host |
| De compartido a propio con datos de terceros: se muestra la causa y se exige resolverla, sin borrar ni reasignar | Caso 2; `f04_operation_mode_test` (bloqueos). En propio las reversiones ya no devuelven actividad a terceros (`db0b10a`) | Cumplido en host |
| Tras el cambio, la interfaz refleja la vigente y las acciones siguen identificables | Casos 1 y 3; navegación de `personal_mode_flows_test` | Cumplido en host |
| Sin conectividad tras activar, consultar y cambiar funciona | 0 peticiones HTTP en los tres casos; todo es local (`app_settings`) | Cumplido en host. **Sin prueba con el teléfono en modo avión** |

## Límites

- **Sin dispositivo:** la prueba en el POCO, con modo avión, está pendiente para la sesión física dedicada.
- **Usabilidad con personas:** el estudio con usuarios (SUS y tareas) es de F10 y no se ejecuta en este bloque; aquí no se afirma nada sobre comprensión real.
- **Base histórica sin titular:** queda en compartido, que es la modalidad por defecto, hasta que se elija el titular, como desde #78.

## Revisiones

- Pruebas automatizadas: ejecutadas con Claude Code el 2026-10-17.
- Revisión de Roderich Rendón: pendiente.
- Revisión del tutor: se registra aparte en GOV-01.
