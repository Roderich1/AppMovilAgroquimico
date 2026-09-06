# EVO-009 — Plan de implementación de voz segura

## Estado

`APPROVED`. Es la primera feature productiva de EVOLUTION-3, después del benchmark.

No añadir plugins/modelos hasta resolver `ADR-002` con evidencia. No incluir intención,
compras, aplicaciones o pagos en esta PR.

## Batch A — Auditoría y ADR

- Confirmar SHA de `main`, cierre de EVOLUTION-2 y gates.
- Auditar navegación, DI, lifecycle y permisos actuales.
- Ejecutar `EVOLUTION-3_SPEECH_ENGINE_BENCHMARK_PLAN.md`.
- Resolver `ADR-002` con privacidad, conectividad, licencia y escape hatch.
- Salida: selección aprobada y ningún cambio de producción todavía.

## Batch B — Puerto y sesión pura

- Definir puerto de transcripción y modelos/eventos de sesión.
- Implementar controlador con estados explícitos.
- Crear fake determinista.
- Probar parciales, final, error, cancelación e interrupción.

## Batch C — Adaptador de plataforma

- Integrar el plugin/SDK seleccionado.
- Configurar permiso Android mínimo.
- Resolver locale `es-BO` con fallback visible.
- Detener y liberar recursos en dispose/background/interrupción.

## Batch D — UX

- Añadir entrada coherente con navegación actual.
- Mostrar estado de micrófono, locale y limitación offline.
- Vista previa editable con Seguir hablando, Reintentar, Entregar y Descartar.
- Explicar que entregar el texto no ejecuta ninguna operación.

## Batch E — Seguridad estructural

- Asegurar que el subsistema Voice no importa repositorios/casos de uso de escritura.
- No persistir audio ni transcripción.
- No registrar texto completo en logs.
- Cubrir ausencia de escritura SQLite con tests/guardas.

## Batch F — Verificación

Ejecutar:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release
```

Después verificar en Pixel 8/API 36:

- permiso concedido/denegado;
- español y locale fallback;
- texto parcial/final;
- edición, continuación, entrega y descarte;
- modo avión;
- background e interrupciones;
- navegación atrás;
- fuente 130 %;
- transcripción larga;
- liberación del micrófono.

## Cierre

Sólo después de reunir evidencia crear:

`EVO-009_FINAL_VERIFICATION.md`

Actualizar backlog, roadmap, riesgos, seguridad, DoD y trazabilidad. La integración con
`EVO-010` ocurre en la PR siguiente, nunca dentro de esta implementación base.
