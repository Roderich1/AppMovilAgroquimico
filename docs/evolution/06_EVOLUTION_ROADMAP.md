# Roadmap de evolución

El orden vigente proviene de una decisión explícita del propietario. No contiene fechas
inventadas y ninguna etapa se considera implementada por existir su documentación.

## EVOLUTION-0 — Gobierno y contrato

- Estado: `VERIFIED` documental.
- Resultado: paquete de evolución, IDs, backlog, DoD y plantillas.
- No añadió funcionalidad de producción.

## EVOLUTION-1 — Portabilidad y diagnóstico

- IDs: `EVO-001`, `EVO-002`, `EVO-003`.
- Estado: `DEFERRED`.
- Incluye compartir `.agrobackup`, recordar última copia y exportar diagnóstico.
- Puede retomarse después mediante decisión explícita.

## EVOLUTION-2 — Lecturas tipadas y exportación de reportes

- IDs: `EVO-004`, `EVO-005`, `EVO-006`.
- Estado: `VERIFIED`; PR #5 fusionada y resultado CSV/PDF aceptado por el propietario. Detalle
  en `features/EVOLUTION-2_IMPLEMENTATION_TRACEABILITY.md` y
  `features/EVOLUTION-2_FINAL_VERIFICATION.md`.
- Orden interno:
  1. typed read models y mappers incrementales;
  2. migración de consumidores necesarios;
  3. compositor neutral de reportes;
  4. CSV;
  5. PDF;
  6. almacenamiento y UX;
  7. CI y Pixel 8.
- Datos: no debe requerir cambio de schema salvo hallazgo independiente y justificado.
- Salida: resultados equivalentes a UI/DB, exportaciones offline y trazabilidad completa.
- No incluye compartir archivos, voz, cloud, sync ni refactor masivo.

## EVOLUTION-3 — Voz segura

- IDs: `EVO-009`, `EVO-010`, `EVO-017`, `EVO-018`, `EVO-019`.
- Estado: `APPROVED` para implementación incremental.
- Precondición: EVOLUTION-2 integrada y cierre documental coherente con la validación aceptada
  por el propietario.
- Flujo común:

```text
Micrófono → transcripción → intención → draft editable → validar → confirmar táctilmente
```

- Orden interno: benchmark/ADR-002 → captura (`EVO-009`) → interpretación (`EVO-010`) → compra
  (`EVO-017`) → aplicación planificada (`EVO-018`) → pago (`EVO-019`).
- Captura e interpretación nunca escriben. Las tres operaciones sólo llaman los casos de uso
  existentes después de una confirmación táctil específica.
- Requiere benchmark local, corpus, privacidad y modo avión sobre dispositivo físico. El
  gate Pixel 8 / API 36 quedó `WAIVED_BY_OWNER` para `ADR-002`.
- No incluye transferencias, reversiones, cierres, borrado, palabra de activación ni consultas.

### Estado de la Fase 0 (benchmark y `ADR-002`) — CERRADA

El propietario ejecutó el corpus de ajuste completo con los tres motores en un **POCO X5 Pro 5G
(Android 12 / API 31)**, en modo avión verificado contra el sistema. `ADR-002` está
**`Accepted`**: motor productivo = **Android `SpeechRecognizer`**; Whisper queda como reserva
técnica **no distribuida**.

| | Android | Whisper tiny | Whisper base |
|---|--:|--:|--:|
| Datos críticos | **81,1 %** | 57,6 % | 66,3 % |
| Sobre silencio | `noMatch` | **`[MÚSICA]`** | `NOT_MEASURED` |
| Peso añadido al APK | **0 B** | +39,2 MiB | +65,4 MiB |

Gate Pixel 8 / API 36: **`WAIVED_BY_OWNER — residual compatibility risk accepted`**
(`RISK-028`). No se ejecutó y no se declara verificado.

Hallazgos que condicionan el alcance: `es-BO` no existe como idioma de reconocimiento y el modo
offline depende del paquete instalado (`RISK-023`); Whisper no produce parciales (`RISK-024`);
**ningún motor reconoce el catálogo agrícola** —5/17 el mejor— por lo que los productos se
resuelven en `EVO-010` contra la base local (`RISK-025`); Whisper afirma texto sobre silencio
(`RISK-026`); y la misma frase dictada dos veces puede dar cantidades distintas (`RISK-027`).

### Estado de la Fase 1 (`EVO-009`) — EN CURSO

`EVO-009` pasó a **`IN_PROGRESS`** en `evolution/evo-009-safe-transcription`. Lo
construido: entrada desde Operaciones, permiso contextual, sesión continua con
reapertura acotada del turno, texto parcial separado del acumulado, vista previa
editable y entrega de **texto de sesión**.

Lo que **no** hace, y no debe leerse como si lo hiciera: no interpreta, no
resuelve productos, no registra compras, pagos ni aplicaciones, y no escribe en
SQLite. Las guardas arquitectónicas fallan si alguna de esas puertas se abre.

Pendiente para `VERIFIED`: prueba en teléfono físico
(`features/EVOLUTION-3_OWNER_DEVICE_TEST_PLAN_EVO-009.md`) y revisión del
propietario. El gate Pixel 8 / API 36 sigue `WAIVED_BY_OWNER`.

`EVO-010` **no ha comenzado**.

## Evoluciones posteriores no aprobadas

- `EVO-020`: consultas de sólo lectura por voz sobre typed reads/reportes.
- Sync/multi-dispositivo, identidad, backup remoto, cifrado e IA.
- Requieren nuevas specs, decisiones y aprobación. No son extensión implícita de EVOLUTION-3.

## Gates entre EVOLUTION-2 y EVOLUTION-3

La primera rama productiva de EVOLUTION-3 no comienza hasta que EVOLUTION-2 tenga:

- implementación integrada;
- format/analyze/test/build verdes;
- CI del SHA final;
- verificación Pixel 8 y prueba CSV/PDF aceptada por el propietario;
- cierre documental coherente con la evidencia;
- ninguna regresión crítica/alta abierta.
