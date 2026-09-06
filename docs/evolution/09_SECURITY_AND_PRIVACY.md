# Seguridad y privacidad

## Estado actual

No existe red, login, token ni analytics. Esto reduce superficie remota, pero base, fotos y
backup no están cifrados. Los roles de persona no son autorización.

## Activos

- Inventario, compras, precios, deudas y pagos.
- Identidad/teléfono de personas.
- Ubicación/nombre de chacos.
- Fotografías de facturas.
- Backups y logs.
- Futuro audio y transcripciones de `EVO-009`.

## Reglas generales

1. Mínimo permiso y solicitud contextual.
2. Mínimo dato fuera del teléfono y retención explícita.
3. No registrar audio, transcripciones completas, montos o paths sensibles por defecto.
4. Un archivo compartido debe advertir que no está cifrado.
5. Cloud exige modelo de amenazas, proveedor, región, borrado y consentimiento.
6. Toda credencial queda fuera del repositorio.

## EVOLUTION-2

- PDF y CSV pueden contener datos financieros y personales; la UI debe advertirlo.
- Generar funciona sin red y no modifica SQLite.
- Generación, almacenamiento y transporte son responsabilidades distintas.
- Fallar o cancelar no deja archivos parciales.
- CSV debe neutralizar celdas que puedan interpretarse como fórmulas.

## EVOLUTION-3 — voz segura y operaciones confirmadas

La aprobación cubre transcripción, drafts tipados y tres operaciones confirmadas. Antes de
fijar un motor debe documentarse:

- motor local, del dispositivo o remoto;
- conectividad real y degradación sin Internet;
- idiomas/locales y fallback;
- datos enviados fuera del teléfono;
- retención de audio y texto;
- permisos Android y lifecycle;
- errores, interrupciones y cancelación.

Controles obligatorios:

- no persistir audio por defecto;
- texto de sesión en memoria salvo acción explícita;
- captura e interpretación no ejecutan dominio ni escriben SQLite;
- no tratar transcripción o intención como operación confirmada;
- compra, aplicación y pago sólo escriben después de validación y confirmación táctil;
- creación de producto/proveedor junto a compra debe ser atómica;
- homónimos, monto/unidad/moneda y adelanto no se autoresuelven;
- no prometer funcionamiento offline si el motor no lo garantiza;
- fake determinista en tests y prueba real en dispositivo.

La política normativa completa está en
`features/EVOLUTION-3_SECURITY_AND_CONFIRMATION_POLICY.md`; el motor se decide en `ADR-002`.

## Respuesta mínima a incidentes

Registrar versión, dispositivo, exposición posible, backup disponible, contención y
recuperación. No corregir inconsistencias borrando historial.
