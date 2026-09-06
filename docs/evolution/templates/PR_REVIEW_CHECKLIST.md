# PR Review Checklist — evolución

## Scope and design

- [ ] Spec `APPROVED`, ID/PR y non-scope visibles.
- [ ] Cambio mínimo; no incluye refactor/upgrade ajeno.
- [ ] ADR presente sólo si la decisión es estructural.

## Domain and data

- [ ] Roles, cobro, dinero, FIFO, stock, campañas, planes y reversiones preservados.
- [ ] Escritura compuesta atómica; reintentos no duplican.
- [ ] Migración forward-only/equivalence/anomalías probadas.
- [ ] Backup/restore compatible o impacto explícitamente aceptado.

## Code and architecture

- [ ] No nueva responsabilidad externa en `AgroRepository` o pantalla.
- [ ] Sin parser, formato, cálculo o query-contract duplicado.
- [ ] Modelos/interfaces aportan seguridad real, no capas vacías.
- [ ] Errores se traducen sin ocultar diagnóstico.

## Security/privacy

- [ ] Permisos mínimos; secretos fuera del repo.
- [ ] Logs/exports/audio/red no filtran datos innecesarios.
- [ ] Consentimiento/retención/offline definidos si aplica.

## Verification

- [ ] Test rojo previo o evidencia equivalente y suite verde.
- [ ] Happy/invalid/boundary/atomicity/failure/recovery/regression.
- [ ] Format, analyze, test y APK release verdes.
- [ ] Android/device verificado para plugin/filesystem/lifecycle.
- [ ] Back, teclado, scroll, rotación, 130 % y doble toque según riesgo.

## Delivery

- [ ] Trazabilidad y documentos actualizados.
- [ ] Version/schema/backup format coherentes.
- [ ] Riesgo residual y rollback revisados.
- [ ] No se movió `v1.0.0-base-stable`.
