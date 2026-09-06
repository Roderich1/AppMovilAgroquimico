# Seguridad y privacidad

## Estado actual

No existe red, login, token ni analytics. Esto reduce superficie remota, pero la base, fotos y
backup no están cifrados. Los roles de persona no son autorización. El riesgo dominante es
acceso físico/pérdida del dispositivo y exposición al compartir un respaldo.

## Activos

- Inventario, compras, precios, deudas y pagos.
- Identidad/teléfono de personas.
- Ubicación/nombre de chacos.
- Fotografías de facturas.
- Backups completos y logs.
- Futuro audio/transcripciones si se aprueba voz.

## Controles actuales a preservar

- Consultas parametrizadas.
- Sin secretos versionados.
- CI con `contents: read`.
- Checksums/manifest y validación antes de restaurar.
- Rollback conjunto DB + fotos.
- Mensajes al usuario cuando un backup queda incompleto.

## Reglas de evolución

1. Mínimo permiso y solicitud contextual.
2. Mínimo dato fuera del teléfono y retención explícita.
3. No registrar audio, montos completos o paths sensibles por defecto.
4. Un archivo compartido debe advertir que no está cifrado y requerir acción del usuario.
5. Autenticación local/biométrica no sustituye cifrado ni recuperación de clave.
6. Cloud exige modelo de amenazas, región/proveedor, borrado, exportación y consentimiento.
7. Toda credencial queda fuera del repo y con rotación/custodia documentada.

## Voz

Antes de aprobar: decidir procesamiento local o remoto, idioma, retención de audio,
conectividad, costos y qué datos se envían. La transcripción nunca se considera intención
confirmada. Operaciones con dinero, stock, reversiones o cierres requieren resumen estructurado
y confirmación inequívoca.

## Respuesta a incidentes mínima

Documentar versión, dispositivo, exposición posible, backup disponible, pasos de contención y
recuperación. No «arreglar» una inconsistencia borrando el historial.
