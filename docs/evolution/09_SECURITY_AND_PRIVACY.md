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

La aprobación cubre transcripción, drafts tipados y tres operaciones confirmadas.

El motor quedó fijado por `ADR-002` (`Accepted`, 2026-09-06): **el reconocimiento del propio
Android**. Lo documentado sobre él:

| Punto | Qué se sabe |
|---|---|
| Motor | **Del dispositivo**, no remoto. Ningún servicio externo, ninguna credencial |
| Conectividad | En el aparato medido transcribió **sin red**, vía SODA. **No se generaliza**: depende del dispositivo, del OEM, de la app de Google y de los modelos instalados |
| Degradación sin Internet | Debe comprobarse **intentando transcribir**; las APIs de disponibilidad no son garantía |
| Idiomas y fallback | `es-BO` **no existe**; `es-ES` puede no estar instalado. Se usa el mejor español disponible y **se muestra cuál** |
| Datos fuera del teléfono | Ninguno por parte de la aplicación. Lo que el servicio del sistema haga queda fuera del control de la app y debe explicarse al usuario |
| Retención | Audio nunca se persiste; el texto vive en memoria de sesión |
| Permisos | Sólo `RECORD_AUDIO`, solicitado en contexto |
| Errores e interrupciones | Estados explícitos; ninguno deja una sesión falsamente aceptada |

Controles obligatorios:

- no persistir audio por defecto;
- texto de sesión en memoria salvo acción explícita;
- captura e interpretación no ejecutan dominio ni escriben SQLite;
- no tratar transcripción o intención como operación confirmada;
- compra, aplicación y pago sólo escriben después de validación y confirmación táctil;
- creación de producto/proveedor junto a compra debe ser atómica;
- homónimos, monto/unidad/moneda y adelanto no se autoresuelven;
- **no prometer funcionamiento offline** si el motor no lo garantiza, ni prometer `es-BO`;
- **no descargar modelos de idioma en silencio**: se informa y se deja decidir;
- **conservar siempre el ingreso manual**: la ausencia de reconocimiento no bloquea la app;
- **no proponer datos a partir de silencio ni de texto no confirmado** por el usuario;
- fake determinista en tests y prueba real en dispositivo.

La política normativa completa está en
`features/EVOLUTION-3_SECURITY_AND_CONFIRMATION_POLICY.md`. El motor está decidido en
`ADR-002` (`Accepted`), junto con la política productiva que obliga a `EVO-009`.

## Modelos de voz locales (Fase 0-bis, `ADR-004` `Proposed`)

Si se adoptara un motor propio —Vosk y/o Whisper embebidos— la superficie cambia: la
aplicación pasaría a **contener y ejecutar modelos**, no sólo a pedirle texto al sistema. Nada
de esto está aceptado todavía; queda escrito antes de medir para que la decisión no se tome
sobre un criterio inventado después.

Lo que gana el usuario: el reconocimiento deja de depender de que el fabricante haya instalado
un paquete de idioma, y deja de pasar por un servicio del sistema que puede usar Internet.

Lo que hay que controlar, y está normado en
`features/EVOLUTION-3_MODEL_DISTRIBUTION_SECURITY_SPEC.md`:

- el audio vive **sólo en memoria nativa**, con duración máxima, y no cruza a Dart;
- no se escribe WAV ni PCM temporal en almacenamiento, en ningún camino, ni siquiera de
  diagnóstico;
- ni la transcripción ni el audio entran en logs, métricas ni informes de fallo;
- los buffers se limpian al terminar, cancelar, perder el permiso o morir el proceso;
- todo modelo llega con manifest, licencia y **SHA-256 verificado antes de extraer**;
- la instalación es atómica, con rollback, y nunca deja una versión a medias;
- **nunca** se descarga un modelo en silencio, y un fallo de modelo no bloquea la aplicación:
  el ingreso manual sigue disponible;
- los modelos no entran en `.agrobackup` ni tocan SQLite;
- la pantalla sólo puede decir «procesamiento local en este teléfono» cuando de verdad esté
  usando el motor local; un fallback al servicio del sistema debe decirse, y no puede llamarse
  local sin evidencia.

Precedente que obliga a esa última regla: en `EVO-009` el paso al reconocedor del sistema se
implementó **preguntando** al usuario y advirtiendo que ese servicio podría usar Internet
(`DEFECTO-004`). El mismo criterio se aplica aquí.

## Respuesta mínima a incidentes

Registrar versión, dispositivo, exposición posible, backup disponible, contención y
recuperación. No corregir inconsistencias borrando historial.
