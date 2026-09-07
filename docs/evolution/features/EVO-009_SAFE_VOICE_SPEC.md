# EVO-009 — Voz segura: transcripción y vista previa

## Identidad

| Campo | Valor |
|---|---|
| Feature | `EVO-009` |
| Etapa | `EVOLUTION-3` |
| Decisión del propietario | Aprobada el 2026-09-06 |
| Estado | `IN_PROGRESS` (implementación en `evolution/evo-009-safe-transcription`) |
| Dependencia | EVOLUTION-2 integrada; `ADR-002` `Accepted` |
| Motor decidido | Android `SpeechRecognizer` (`ADR-002`, 2026-09-06). Whisper es reserva no distribuida |
| Rama prevista | `evolution/evo-009-safe-transcription` |

Este ID conserva su significado original: captura y transcripción seguras. Las intenciones y
operaciones aprobadas viven en specs separadas y no deben mezclarse en la misma PR.

## Objetivo

Reducir el tecleo en campo mediante captura y transcripción continua con una vista previa
editable y control humano. Esta feature no interpreta ni ejecuta operaciones de dominio; es la
fuente reemplazable para `EVO-010`.

## Flujo autorizado

```text
Micrófono
→ solicitar/validar permiso
→ escuchar
→ recibir texto parcial/final
→ vista previa editable
→ seguir hablando / editar / entregar texto final / descartar
```

Entregar texto confirma únicamente el resultado de la sesión para el siguiente componente. No
confirma una compra, pago, aplicación, transferencia, reversión, cierre, cantidad ni cambio de
inventario.

## Alcance

- Puerto `SpeechTranscriptionPort` o nombre equivalente.
- Adaptador de plataforma reemplazable.
- Controlador de sesión independiente de widgets y repositorio.
- Texto parcial y final.
- Vista previa editable.
- Seguir hablando, editar, reintentar, entregar texto y descartar.
- Permiso contextual de micrófono.
- Idioma español: se **pide** `es-BO`, pero **no se promete** — no existe como idioma de
  reconocimiento. Se usa el mejor español instalado o soportado, con fallback **visible**.
- Manejo de lifecycle, interrupciones, denegación y servicio no disponible.
- Tests con fake y verificación en dispositivo físico. El gate Pixel 8 / API 36 está
  `WAIVED_BY_OWNER`; si aparece un aparato API 36 se ejecuta como regresión adicional.
- **Ingreso manual siempre disponible**, incluso sin reconocimiento.

## Fuera de alcance

- Interpretar intención o entidades agrícolas.
- Convertir texto en comandos tipados.
- Ejecutar `AgroRepository`, casos de uso, SQL o SQLite.
- Registrar compras, pagos, aplicaciones o transferencias.
- Confirmar cantidades, costos, moneda, productos, personas o chacos.
- Guardar audio o transcripciones como historial operativo.
- IA generativa, backend, sync o autenticación.
- Clasificador, extractor y drafts de `EVO-010`; se integran después mediante el puerto.

## Arquitectura

```text
VoiceScreen
    ↓
VoiceSessionController
    ↓
SpeechTranscriptionPort
    ↓
PlatformSpeechTranscriber
```

El puerto no expone SQLite ni operaciones agrícolas. El controlador produce un resultado de
sesión en memoria y estados observables.

## Estados mínimos

| Estado | Significado |
|---|---|
| `idle` | Sin sesión activa |
| `requestingPermission` | Esperando permiso |
| `listening` | Micrófono activo |
| `processing` | Esperando resultado final |
| `preview` | Texto editable disponible |
| `ready` | Texto de sesión listo para entregar, sin ejecutar dominio |
| `cancelled` | Sesión descartada |
| `denied` | Permiso rechazado |
| `unavailable` | Servicio/locale no disponible |
| `error` | Fallo recuperable y seguro |

### Refinamiento aplicado en la implementación

La tabla anterior es la mínima. Al construir la sesión, tres de sus estados
resultaron **insuficientes para decidir qué ofrecer al usuario**, y por eso el
código usa una lista de catorce. No se retira nada: se separa.

| Estado mínimo | Estados implementados | Por qué hizo falta separar |
|---|---|---|
| `denied` | `permissionDenied`, `permissionPermanentlyDenied` | En el primero se vuelve a pedir el permiso; en el segundo Android ya no pregunta y la única salida son los ajustes. Ofrecer «reintentar» en el segundo caso sería mentir |
| `unavailable` | `languageUnavailable`, `recognizerUnavailable` | Sin español instalado se explica cómo instalarlo; sin reconocedor no hay nada que instalar. Los consejos son incompatibles |
| `error` | `recoverableError`, `fatalError` | Sólo el primero admite reintentar sin acción del usuario |
| — | `starting`, `stopping` | Son las transiciones donde se deshabilitan los botones. Sin estado propio, evitar la doble acción exigiría un booleano paralelo, que es exactamente la contradicción que esta tabla evita |

`ready` **no** tiene estado propio. Entregar el texto deja un resultado en la
sesión y la deja en `preview`: convertirlo en estado terminal habría obligado a
salir de él para seguir editando, y `EVO-009-REQ-001` exige que la vista previa
siga siendo editable siempre.

### Lista de idiomas: exacta y probada

`ADR-002` obliga a documentar el fallback. Es éste, en este orden:

```text
es-US · es-BO · es-419 · es-PE · es-AR · es-CL · es-CO · es-MX · es-ES · es
```

- Se **pide** `es-US` y se muestra el que el motor **aceptó**. El locale
  solicitado lo revisó el propietario el 2026-09-06 durante el gate del HONOR
  JDY-LX3P; el detalle y la evidencia están en la sección «Revisión 2026-09-06»
  de `ADR-002`.
- `es-US` es el **primer intento**, no una promesa: si falla se recorre el resto.
- `es-BO` sigue en la lista, en segundo lugar, porque es el país del usuario.
- Con `checkRecognitionSupport` disponible (API 33+) los instalados se adelantan;
  sin él (API 31, el aparato de referencia) se recorre la lista **intentando y
  observando**, que es lo que exige `EVO-009-REQ-014`.
- Sólo `LANGUAGE_NOT_SUPPORTED` / `LANGUAGE_UNAVAILABLE` avanzan al siguiente
  candidato. Un permiso denegado no mejora cambiando de idioma, y recorrer diez
  candidatos ante un micrófono denegado sería el bucle que `EVO-009-REQ-017`
  prohíbe.
- Agotada la lista: `languageUnavailable`, con instrucciones y **sin descargar
  nada**.

### Cómo se combinan la voz y las correcciones manuales

Regla única: **el texto nuevo se añade al final; nunca reescribe.**

- El texto de sesión es del usuario y se puede editar entero.
- Un segmento del motor se concatena al final de lo que haya.
- El parcial vive **separado** y no entra hasta que el motor lo confirma.
- Deshacer revierte el último añadido automático y **se desactiva en cuanto el
  usuario edita**: deshacer entonces borraría su propia corrección.

Es la única regla que no puede perder una corrección, porque el motor nunca toca
lo ya escrito.

### Continuidad controlada

`SpeechRecognizer` cierra la escucha al detectar silencio aunque el usuario
quiera seguir. La sesión reabre el turno **sólo mientras el usuario la mantenga
activa**, y frena con: máximo de turnos improductivos seguidos, backoff que se
duplica hasta un tope, tope absoluto de turnos y duración máxima de sesión. Un
turno con texto pone el contador a cero. **No se reabre nunca** ante permiso
denegado, cancelación, error fatal, segundo plano o salida de la pantalla.

## Requisitos

| ID | Requisito |
|---|---|
| EVO-009-REQ-001 | La transcripción siempre pasa por una vista previa editable. |
| EVO-009-REQ-002 | Entregar texto no llama repositorios, casos de uso ni SQLite. |
| EVO-009-REQ-003 | Descartar elimina el texto de sesión y libera el micrófono. |
| EVO-009-REQ-004 | El permiso se solicita en contexto y se manejan denegación temporal/permanente. |
| EVO-009-REQ-005 | Salir, ir a background o sufrir una interrupción detiene/libera recursos. |
| EVO-009-REQ-006 | Audio no se persiste por defecto. |
| EVO-009-REQ-007 | Transcripción permanece en memoria salvo acción explícita permitida. |
| EVO-009-REQ-008 | La UI muestra locale y no promete offline si el motor no lo garantiza. |
| EVO-009-REQ-009 | Plugin/SDK queda aislado detrás de un puerto testeable. |
| EVO-009-REQ-010 | Errores no modifican estado operativo ni dejan una sesión falsa aceptada. |
| EVO-009-REQ-011 | La UI diferencia transcripción, interpretación y confirmación de operación. |
| EVO-009-REQ-012 | La sesión admite texto parcial acumulativo y continuar hablando sin reiniciar. |
| EVO-009-REQ-013 | La app solicita preferentemente reconocimiento offline / on-device. |
| EVO-009-REQ-014 | No confía únicamente en `isRecognitionAvailable()`, `isOnDeviceRecognitionAvailable()` ni en la lista de idiomas instalados: intenta la operación y observa el resultado real. |
| EVO-009-REQ-015 | La UI muestra locale solicitado, locale utilizado, disponibilidad de modo offline, si falta un modelo y si el error es recuperable. |
| EVO-009-REQ-016 | No puede prometer `es-BO`. Usa el mejor español instalado o soportado con fallback visible. |
| EVO-009-REQ-017 | Sin reconocimiento disponible: no bloquea la app, no reintenta infinitamente, no descarga silenciosamente, muestra instrucciones y mantiene la edición manual. |
| EVO-009-REQ-018 | La voz nunca confirma operaciones. |
| EVO-009-REQ-019 | Los resultados parciales son sólo texto provisional; no alimentan ninguna decisión. |
| EVO-009-REQ-020 | Todo texto pasa después por `EVO-010`: resolución local, validación y borrador editable. |

## Motor decidido

`ADR-002` está **`Accepted`**: el motor productivo inicial es el reconocimiento de Android
(`android.speech.SpeechRecognizer`). Whisper queda como reserva técnica **no distribuida**.

Lo que la evidencia obliga a asumir en la implementación:

| Hecho medido | Consecuencia para `EVO-009` |
|---|---|
| `es-BO` da error 12 `LANGUAGE_NOT_SUPPORTED` | No se promete `es-BO`; se muestra el locale realmente usado |
| `es-ES` dio error 13 `LANGUAGE_UNAVAILABLE` | Puede faltar el modelo de idioma; hay que decirlo, no descargarlo en silencio |
| Sólo funcionó `es-US` | Se usa el mejor español disponible, no uno fijo |
| `isOnDeviceRecognitionAvailable()` devolvió `false` donde el offline **sí** funcionaba | La API no es garantía: hay que intentar transcribir y observar |
| Silencio devuelve `noMatch` | Ausencia de habla no es texto; nunca se propone un dato |
| La misma frase dio `12` y `dos` en dos tomas | Cantidades y montos exigen confirmación visible del usuario |
| 5/17 productos correctos | La transcripción **no** precarga productos; eso es `EVO-010` |

La aprobación de la feature no aprueba un proveedor remoto. Sigue prohibido.

## Privacidad

- No persistir audio.
- No incluir transcripción completa en logs.
- No enviar audio fuera del dispositivo sin decisión explícita, aviso y documentación.
- Minimizar identificadores y metadata.
- Explicar si el servicio del dispositivo puede usar red. En el aparato medido la
  transcripción corrió en **SODA**, local, sin red — pero eso **no se generaliza**:
  depende del dispositivo, del OEM, de la app de Google y de los modelos instalados.

## Pruebas

- Permiso concedido, denegado y permanentemente denegado.
- Inicio, parcial, final y vista previa.
- Edición, continuación, entrega y descarte.
- Servicio/locale no disponible.
- Error, timeout, doble toque e interrupción.
- Background, dispose y navegación atrás liberan el micrófono.
- Fake determinista del puerto.
- Guardas que demuestren ausencia de llamadas a SQLite/dominio.
- Fuente 130 %, transcripción larga y orientación.
- Prueba real de micrófono en dispositivo físico.
- Modo avión **verificado contra el sistema**, no declarado por quien prueba.
- Ausencia de reconocimiento: la app sigue usable con ingreso manual.
- Pixel 8 / API 36: gate `WAIVED_BY_OWNER`; si aparece el aparato, regresión adicional.

## Criterios de aceptación

- [ ] Flujo completo produce y edita texto.
- [ ] Entregar sólo produce texto de sesión para el siguiente componente.
- [ ] Ningún camino escribe en SQLite o ejecuta dominio.
- [ ] Permiso, lifecycle, error y cancelación son seguros.
- [ ] Política local/remota y retención están documentadas.
- [ ] Tests, CI y build tienen evidencia en dispositivo físico.
- [ ] El ingreso manual funciona con el reconocimiento no disponible.

## Estado de la implementación

`IN_PROGRESS`. Construido y cubierto con pruebas automatizadas: puerto,
adaptador de Android, sesión con continuidad, política de idioma, pantalla y
guardas arquitectónicas. Detalle requisito a requisito en
`EVO-009_IMPLEMENTATION_TRACEABILITY.md`.

**Pendiente para `VERIFIED`**: prueba en dispositivo físico según
`EVOLUTION-3_OWNER_DEVICE_TEST_PLAN_EVO-009.md` y revisión del propietario. El
gate Pixel 8 / API 36 sigue `WAIVED_BY_OWNER` y no se declara probado.

## Rollback

Retirar ruta, UI, controlador y adaptador. No existe downgrade de datos porque EVO-009 no
cambia schema ni persiste audio/transcripciones.
