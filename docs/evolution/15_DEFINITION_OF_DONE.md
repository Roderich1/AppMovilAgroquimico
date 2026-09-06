# Definition of Done de una evolución

Una feature sólo es `VERIFIED` cuando todos los controles aplicables están satisfechos.

## Producto y alcance

- [ ] Decisión del propietario registrada; spec `APPROVED`.
- [ ] Flujos, non-scope, errores y criterios de aceptación cumplidos.
- [ ] No se introdujeron requisitos inventados.

## Implementación

- [ ] Cambio mínimo, sin refactor masivo mezclado.
- [ ] Invariantes protegidas fuera de la UI.
- [ ] Operaciones compuestas atómicas e idempotencia/reintento definidos.
- [ ] Sin lógica de dinero, parser o FIFO duplicada.

## Datos y recuperación

- [ ] Migración forward-only y equivalencia fresh/migrated, si aplica.
- [ ] Anomalías preservadas y comunicadas.
- [ ] Compatibilidad de backup declarada y restore probado.
- [ ] Rollback operativo practicable.

## Calidad

- [ ] Happy/invalid/boundary/atomicity/failure/recovery/regression.
- [ ] Format, analyze, test y APK release verdes en CI.
- [ ] Ningún test debilitado ni exclusión nueva sin justificación.
- [ ] Volumen/performance medidos cuando el riesgo lo exige.

## Mobile, UX y seguridad

- [ ] Pixel 8/device verification si toca plugin o comportamiento móvil.
- [ ] Teclado, back, rotación, 130 %, listas grandes y doble toque según aplique.
- [ ] Permisos mínimos y datos/logs revisados.
- [ ] Errores accionables; fallos externos no corrompen ni bloquean innecesariamente.

## Controles adicionales para voz

- [ ] Motor elegido mediante benchmark reproducible y ADR aceptado.
- [ ] Corpus de aceptación separado incluye ruido, aliases, números, homónimos y correcciones.
- [ ] Cero falsa aceptación de datos críticos ambiguos en el corpus de cierre.
- [ ] Cero escrituras durante captura, interpretación, edición, cancelación y descarte.
- [ ] Confirmación táctil específica; voz nunca confirma una escritura.
- [ ] Audio/transcripción efímeros y logs sin contenido sensible.
- [ ] Permiso, modo avión, lifecycle, interrupción y liberación de micrófono probados.
- [ ] Latencia, memoria, tamaño, batería/temperatura medidos en Pixel 8 y un equipo inferior.
- [ ] Paridad y atomicidad con compra/aplicación/pago manual según cada feature.

## Entrega

- [ ] Trazabilidad requisito → cambio → test → evidencia.
- [ ] Documentación, backlog, riesgos y estado corriente actualizados.
- [ ] Release/version/schema/backup format coherentes.
- [ ] PR revisado; SHA y CI run registrados.
