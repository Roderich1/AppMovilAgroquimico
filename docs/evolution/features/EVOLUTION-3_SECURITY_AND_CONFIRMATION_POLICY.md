# EVOLUTION-3 — Política de seguridad, privacidad y confirmación

## Regla principal

La voz es una entrada no confiable. Audio, transcripción, intención, entidades y confianza son
propuestas. Sólo el borrador tipado validado y confirmado táctilmente puede llegar al dominio.

## Matriz de acciones

| Acción | Voz prepara | Edición manual | Confirmación táctil | Autoejecución |
|---|:--:|:--:|:--:|:--:|
| Compra | Sí | Sí | Obligatoria | Nunca |
| Crear producto/proveedor dentro de compra | Sí | Sí | Obligatoria junto a compra | Nunca |
| Aplicar plan | Sí | Sí | Obligatoria | Nunca |
| Pago de cuenta | Sí | Sí | Obligatoria | Nunca |
| Consulta de sólo lectura futura | Sí | Sí | No escribe | No aplica |
| Reversión/cierre/transferencia/borrado | Fuera de alcance | Flujo actual | Flujo actual | Nunca |

## Permiso y lifecycle

- Pedir `RECORD_AUDIO` al tocar por primera vez una función de voz, con explicación previa.
- Si se deniega, mantener el formulario manual completamente funcional.
- Mostrar indicador persistente mientras el micrófono está activo y un control claro para
  detener/cancelar.
- Liberar captura al pausar, bloquear pantalla, recibir llamada, perder foco, navegar o cerrar.
- No escuchar en segundo plano ni activar por palabra clave.

## Retención

- Audio: memoria temporal; eliminar al terminar/cancelar/error. No persistir por defecto.
- Transcripción: memoria de la sesión; no incluir texto completo en logs ni analytics.
- Borrador: memoria hasta confirmar o descartar; si se propone recuperación tras cierre, debe
  aprobarse como otra feature y cifrar/minimizar los datos.
- Diagnóstico: sólo estados/códigos, tiempos agregados y versiones, sin nombres, frases,
  montos, teléfonos ni rutas sensibles.

## Procesamiento externo

La primera opción debe evaluarse offline. Cualquier motor remoto exige antes:

- ADR adicional con proveedor, región, transporte, retención y eliminación;
- consentimiento informado distinto del permiso de micrófono;
- política de degradación sin red;
- secretos fuera del APK/repositorio;
- evaluación legal y de costos.

## Confirmación segura

- Botón con verbo y objeto: `Registrar compra`, `Aplicar planificación`, `Registrar pago`.
- Resumen completo visible y desplazable, incluso horizontal y a escala 130 %.
- Cambios nuevos después de revisar invalidan el estado `listo` y reejecutan validación.
- Durante escritura, desactivar doble toque y usar protección contra duplicados/reintentos.
- Error conserva el draft, explica qué ocurrió y no afirma éxito sin resultado del dominio.
- Éxito detiene micrófono, limpia audio/transcripción y muestra el registro creado.

## Datos críticos que nunca se autoresuelven con baja confianza

- Persona/propietario/proveedor homónimo.
- Producto o chaco con varios candidatos.
- Cantidad, unidad, moneda, precio y tipo de cambio.
- Plan cuando existen varios candidatos.
- Tratamiento de excedente como adelanto.
- Creación de catálogo.

## Amenazas y controles

| Amenaza | Control mínimo |
|---|---|
| Transcripción incorrecta | Draft + texto interpretado + edición + confirmación |
| Ruido genera intent | Tap-to-talk, intención soportada y no autoejecución |
| Dato sensible sale del teléfono | motor local preferido; ADR/consentimiento si remoto |
| Reproducción/doble toque duplica operación | una confirmación activa + idempotencia/revalidación |
| Catálogo incorrecto se crea | estado `newProposed` y confirmación explícita |
| Logs filtran frases o montos | allowlist de métricas y redacción |

