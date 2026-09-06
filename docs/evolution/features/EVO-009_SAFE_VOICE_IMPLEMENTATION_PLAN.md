# EVO-009 — Plan de implementación de voz segura

## Estado

`APPROVED`, bloqueado hasta que EVOLUTION-2 esté integrada y verificada.

No crear la rama ni añadir plugins mientras la dependencia no se cumpla.

## Batch A — Auditoría y ADR

- Confirmar SHA de `main`, estado de EVOLUTION-2 y gates.
- Auditar navegación, DI, lifecycle y permisos actuales.
- Evaluar motores de Speech-to-Text con fuentes primarias.
- Crear ADR local/remoto con privacidad, conectividad y escape hatch.
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
- Vista previa editable con Aceptar, Reintentar y Descartar.
- Explicar que aceptar no ejecuta ninguna operación.

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
- edición, aceptación y descarte;
- modo avión;
- background e interrupciones;
- navegación atrás;
- fuente 130 %;
- transcripción larga;
- liberación del micrófono.

## Cierre

Sólo después de reunir evidencia crear:

`EVO-009_FINAL_VERIFICATION.md`

Actualizar backlog, roadmap, riesgos, seguridad, DoD y trazabilidad. No añadir `EVO-010` al
mismo PR.

