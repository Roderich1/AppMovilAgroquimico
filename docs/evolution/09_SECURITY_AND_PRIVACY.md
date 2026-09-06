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

## EVO-009 — voz segura

La aprobación cubre sólo transcripción y vista previa. Antes de implementar debe documentarse:

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
- no ejecutar dominio ni escribir SQLite;
- no tratar transcripción como intención confirmada;
- no prometer funcionamiento offline si el motor no lo garantiza;
- fake determinista en tests y prueba real en dispositivo.

## Respuesta mínima a incidentes

Registrar versión, dispositivo, exposición posible, backup disponible, contención y
recuperación. No corregir inconsistencias borrando historial.

