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

## Disparadores de revisión

Revisar al analizar/ aprobar una feature, cambiar schema/backup/plugin, añadir red o modificar
roles/dinero/FIFO. Riesgos nuevos se agregan; no se borra historia, se cierran con estado y
evidencia en la spec.
