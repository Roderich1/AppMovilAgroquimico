# GATE-F03 (#23) — Decisión para el alcance académico

## Identificación y autoridad

- **Proyecto:** Agrocuentas, Proyecto de Grado 2026.
- **Fase:** F03, activación online y sesión offline. **Gate:** [#23](https://github.com/Roderich1/AppMovilAgroquimico/issues/23). Tarea ligada: [#76](https://github.com/Roderich1/AppMovilAgroquimico/issues/76) (F03-RES-02, compuerta de primera activación).
- **Fecha de la decisión:** 2026-10-17 (`America/La_Paz`). La sesión A de Claude Code la registra el mismo día.
- **Procedencia.** Es una decisión técnica **por delegación de Roderich1**, propietario del proyecto. Consta en `_briefs/CIERRE_F01_F09_Y_SIGUIENTES_SESIONES_2026-10-17.md` §2, tabla «Gates y matriz de sincronización». Se toma sobre la propuesta integrada BE `docs/evaluation/F03_F05_F06_PROPUESTAS_DECISION.md` (BE #134):

  > «F03 | Aceptar Passed para el alcance académico y los residuales enumerados en su acta | Registrar decisión con fecha real y base; después cerrar #76. Conservar las evidencias parciales de AUTH que no tienen archivo en `docs/evidence/`»

- **Lo que esta decisión no es:**
  - una inspección personal del autor;
  - una revisión ni una aprobación del tutor (se registra en GOV-01, BE #105);
  - una aprobación institucional.

  Se registra como revisión técnica automatizada y decisión por delegación.

## Decisión

- `GATE_F03 = PASSED`
- `SCOPE = ACADEMIC`
- `EVIDENCE = PARTIAL`, porque los residuales de abajo se conservan
- **#76:** se cierra con la evidencia de [F03_F04_DEVICE_2026-10-17.md](F03_F04_DEVICE_2026-10-17.md)

**Base de referencia:**
- Mobile `main` `ec69ae81a6e1168dfb4dd8d7b8a7181f1da1fcd2`, con CI 39063721692 SUCCESS: 1446 pasan, 3 omitidas, más 17 pruebas de fechas en America/La_Paz y el build de release.
- Backend `main` `2825de50c58d7b8b2b09288fde6306c8b7d06e83`.
- **Las evidencias físicas conservan sus SHA específicos**, sin reatribuirse a esta base:
  - #71: MOB `94e7d24`/`5527784`, BE `c2acbd4`/`063437d`;
  - sesión del 2026-10-17: V = `1902e6e`, v7 = `905e67c`, BE `e2263b0`.
- Lo integrado después (#110 campañas, #112 voz y #111 protocolo) no toca el arranque, la activación ni la sesión. Lo cubre la CI de `main`.

## Fundamento: criterios de #23

El acta propuesta es [GATE_F03_EVALUATION.md](GATE_F03_EVALUATION.md).

| Criterio | Estado en el acta | Procedencia |
|---|---|---|
| 1. #18 AUTH-01 | Cumplido para el gate. Hueco: 403/404 y `ApiEndpointConfig.fromEnvironment` sin prueba | CI + DEVICE indirecto |
| 2. #19 AUTH-02 | Cumplido | DEVICE |
| 3. #20 AUTH-03 | Cumplido (P13: sesión ilegible sin borrar ni tratar como nueva) | DEVICE |
| 4. #21 AUTH-04 | Cumplido (P6, P7 y P11 sin red) | DEVICE |
| 5. #22 AUTH-05 | Cumplido (401 real en #71) | DEVICE |
| 6. Primera instalación online, operación sin red, refresh inválido sin destruir SQLite | Cumplido (P1, P3, P6, P7 y P11; #71 E-1/E-2) | DEVICE + CI |

**#76:** sus cinco criterios están PASS en host y en el POCO (P1, P2, P11, P12 y P13).

## Residuales que se conservan (NOT_MEASURED, límite declarado)

- DEVICE-19-C (corte de red durante la activación) y DEVICE-19-F;
- DEVICE-21-E (almacén cifrado del sistema dañado);
- Auto Backup, D2D y corte de energía (#20); multi-isolate, que no se reclama;
- logcat de valores opacos de la sesión del 2026-10-15 (#71), y E-1 sin el escaneo ampliado;
- #76: con «sesión dañada sin activar» y con «sesión de otro Member», la pantalla muestra la condición sin una salida automática (criterio B de #78);
- un solo modelo de teléfono (POCO X5 Pro 5G, Android 12).

**Evidencias parciales de AUTH que se conservan:** MOB #18–#22 siguen con `Evidence = Partial`, porque sus evidencias están en `docs/evolution/features/` y no en `docs/evidence/`. Además, #18 tiene huecos de prueba. No se marcan `Verified` por esta decisión.

## Revisiones

- **Registro:** sesión A de Claude Code, el 2026-10-17, sobre las actas versionadas y sin repetir pruebas.
- **Revisión personal de Roderich Rendón:** no consta.
- **Revisión del tutor:** se registra aparte en GOV-01.
