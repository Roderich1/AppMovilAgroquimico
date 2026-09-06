# Registro de riesgos de evolución

Escala: probabilidad e impacto `L/M/H`. Owner es responsabilidad lógica, no persona asignada.

| ID | Riesgo | P | I | Mitigación/trigger | Owner lógico |
|---|---|:--:|:--:|---|---|
| RISK-001 | Regresión contable | M | H | Tests exactos y no cambiar políticas incidentalmente | Domain |
| RISK-002 | Stock/costo FIFO incorrecto | M | H | Motor único, conservación y atomicidad | Inventory |
| RISK-003 | Corrupción/pérdida en migración | M | H | Forward-only, anomalías, equivalencia, backup | Data |
| RISK-004 | Backup futuro incompatible | M | H | Matriz de lectura, manifest y restore E2E | Backup |
| RISK-005 | `AgroRepository` absorbe nuevos subsistemas | H | M | Boundary cuando se activa trigger | Architecture |
| RISK-006 | Cast/alias falla en runtime | H | M | Modelos tipados en lecturas tocadas | Data/UI |
| RISK-007 | Plugin difiere entre test y Android | M | H | Fake semántico + Pixel 8 | Mobile QA |
| RISK-008 | Listas crecen y degradan UX/performance | M | M | límites, búsqueda SQL, perfiles con volumen | Product/Data |
| RISK-009 | Backup compartido expone datos | M | H | acción explícita, aviso, destino controlado | Security |
| RISK-010 | Voz interpreta entidad/cantidad errónea | H | H | preview, desambiguación, confirmación, no autoejecución | Voice/Domain |
| RISK-011 | Cloud rompe modo offline | M | H | local source of truth/degradación definida | Sync |
| RISK-012 | Conflictos multi-dispositivo | H | H | UUID/versiones/merge policy antes de sync | Sync/Data |
| RISK-013 | Dependencia abandonada | M | M | health/licencia/escape hatch antes de adoptar | Architecture |
| RISK-014 | Datos sensibles en logs | M | H | allowlist, redacción, retención | Security |
| RISK-015 | Push directo evita CI | M | H | proteger `main` y requerir checks antes de PRs evolutivos | Release |
| RISK-016 | Motor local degrada memoria, batería o latencia | M | H | benchmark Pixel 8 + gama media/baja antes de adoptar | Voice/Mobile QA |
| RISK-017 | Audio/transcripción sensible sale o queda almacenado | M | H | local preferido, memoria efímera, logs redactados, ADR si remoto | Security |
| RISK-018 | Voz crea catálogo equivocado | H | H | candidatos, aliases, estado `newProposed` y confirmación explícita | Voice/Catalog |
| RISK-019 | Reintento/doble toque duplica compra/aplicación/pago | M | H | lock UI, revalidación, transacción e idempotencia | Application/Domain |
| RISK-020 | Intento de compra deja producto o movimientos parciales | M | H | creación + compra en unidad atómica y fallos inducidos | Purchase/Data |
| RISK-021 | Pago excedente se convierte silenciosamente en adelanto | M | H | decisión explícita y saldo antes/después | Accounts/Product |
| RISK-022 | Plan cambia entre preview y confirmación | M | H | relectura/revalidación y conflicto bloqueante | Application/Inventory |
| RISK-023 | `es-BO` no existe como idioma de reconocimiento y el modo offline depende de un paquete de idioma ya instalado | H | H | Medido en teléfono real: `es-BO` da error 12 y `es-ES` error 13; sólo funcionó `es-US`. La UI debe declarar el locale realmente usado y no prometer `es-BO`. `isOnDeviceRecognitionAvailable()` no sirve como garantía: devuelve `false` donde el offline sí funciona | Voice/Product |
| RISK-024 | `whisper.cpp` no emite resultados parciales y la experiencia prometida asume texto en vivo | H | M | Confirmado en teléfono real: cero parciales y 1,2–2,9 s de espera tras detener. Si `ADR-002` elige Whisper, o se acepta una UX sin texto en vivo o se mide aparte la transcripción por trozos | Voice/Product |
| RISK-025 | Ningún motor reconoce los nombres de producto y la transcripción cruda no puede precargar un borrador | H | H | Medido: 5/17 productos correctos en el mejor motor. El reconocimiento se resuelve contra la base local en `EVO-010`, nunca en el motor, y la frontera de confirmación de `ADR-003` es obligatoria | Voice/Product |
| RISK-026 | `whisper.cpp` afirma texto sobre silencio y lo marca como resultado válido | M | H | Reproducido en teléfono real: devolvió `[MÚSICA]` sin habla y sin error. Si se elige Whisper, hace falta una guarda explícita de "sin habla" antes de proponer cualquier dato | Voice/Product |
| RISK-027 | La misma frase dictada dos veces da datos críticos distintos | M | H | Medido: 33,3 % de coincidencia entre dos tandas, con una cantidad que cambió de `12` a `dos`. No se corrige con diccionarios; obliga a que el usuario revise cantidades y montos antes de confirmar | Voice/Product |

## Evidencia incorporada

`RISK-023` a `RISK-027` no son hipótesis: salen de mediciones sobre un teléfono real
(POCO X5 Pro 5G, Android 12 / API 31, modo avión verificado contra el sistema), registradas en
`features/EVOLUTION-3_SPEECH_ENGINE_BENCHMARK_RESULTS.md`.

`RISK-016` queda **parcialmente cerrado**: memoria pico (158 MiB Android, 276–328 MiB Whisper) y
latencias están medidas; CPU y batería siguen `NOT_MEASURED` porque el teléfono estuvo cargando
toda la sesión. El gate del Pixel 8 / API 36 sigue abierto.

## Disparadores de revisión

Revisar al analizar/ aprobar una feature, cambiar schema/backup/plugin, añadir red o modificar
roles/dinero/FIFO. Riesgos nuevos se agregan; no se borra historia, se cierran con estado y
evidencia en la spec.
