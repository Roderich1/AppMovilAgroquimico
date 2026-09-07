# EVOLUTION-3 — Matriz de aceptación del motor híbrido

## Identidad de la corrida

| Campo | Valor |
|---|---|
| Commit de benchmark | `PENDING` |
| Commit whisper.cpp | `PENDING` |
| Vosk API | `PENDING` |
| Vosk model ID/SHA-256 | `PENDING` |
| Whisper model ID/SHA-256 | `PENDING` |
| APK/SHA-256 | `PENDING` |
| POCO fecha/operador | `PENDING` |
| HONOR fecha/operador | `PENDING` |

## Resultado comparativo

| Métrica | Android baseline | Vosk | Whisper small | Híbrido | Umbral | Estado |
|---|---:|---:|---:|---:|---:|---|
| Datos críticos correctos | 81,1 % | PENDING | PENDING | PENDING | > 81,1 % | PENDING |
| Productos correctos | 5/17 | PENDING | PENDING | PENDING | >= 12/17 | PENDING |
| Cantidades correctas | 17/17 | PENDING | PENDING | PENDING | >= 17/17 | PENDING |
| Precios correctos | 8/8 | PENDING | PENDING | PENDING | >= 8/8 | PENDING |
| Montos correctos | 6/7 | PENDING | PENDING | PENDING | >= 6/7 | PENDING |
| WER mediana | 0,167 | PENDING | PENDING | PENDING | <= 0,167 | PENDING |
| Primer parcial p50 | 1741 ms | PENDING | N/A | PENDING | <= 800 ms | PENDING |
| Primer parcial p95 | PENDING | PENDING | N/A | PENDING | <= 1500 ms | PENDING |
| Final p50 <=20 s | 17 ms | PENDING | PENDING | PENDING | <= 2500 ms | PENDING |
| Final p95 <=20 s | PENDING | PENDING | PENDING | PENDING | <= 5000 ms | PENDING |
| RTF p95 <=60 s | PENDING | PENDING | PENDING | PENDING | <= 0,50 | PENDING |
| RAM pico total | 158 MiB | PENDING | PENDING | PENDING | <= 1,2 GB | PENDING |
| Texto sobre no-habla | 0 | PENDING | PENDING | PENDING | 0 | PENDING |
| Crash/ANR/OOM 30 sesiones | 0 | PENDING | PENDING | PENDING | 0 | PENDING |
| Funciona limpio en modo avión | depende del sistema | PENDING | PENDING | PENDING | Sí | PENDING |

Completar una tabla por dispositivo además del resumen; no mezclar POCO y HONOR en un promedio
que esconda fallos por OEM/API.

## Guardrails binarios

| Gate | POCO API 31 | HONOR API 36 | Evidencia |
|---|---|---|---|
| Instalación limpia | PENDING | PENDING | |
| Modelo auténtico y hash válido | PENDING | PENDING | |
| Primera ejecución sin red | PENDING | PENDING | |
| Una sola captura de audio | PENDING | PENDING | |
| Audio nunca escrito | PENDING | PENDING | |
| Cancelación libera micrófono | PENDING | PENDING | |
| Lifecycle/interrupciones | PENDING | PENDING | |
| Silencio/ruido no producen texto aceptado | PENDING | PENDING | |
| Edición manual preservada | PENDING | PENDING | |
| Inventario y cuentas sin cambios | PENDING | PENDING | |
| CPU/batería/temperatura medidos | PENDING | PENDING | |
| Licencias/atribuciones completas | PENDING | PENDING | |

## Decisión

| Campo | Valor |
|---|---|
| Candidato recomendado | `PENDING` |
| Umbrales incumplidos | `PENDING` |
| Riesgos aceptados | `PENDING` |
| ADR-004 | `Proposed` |
| Decisión del propietario | `PENDING` |
| Fecha | `PENDING` |

No cambiar `ADR-004` a `Accepted` si quedan métricas críticas `NOT_MEASURED`, si existe texto
aceptado sobre no-habla o si sólo uno de los dos dispositivos obligatorios fue probado.

