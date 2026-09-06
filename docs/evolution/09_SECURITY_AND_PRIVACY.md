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

### Qué implementa `EVO-009` de estos controles

La captura ya está construida. Estos son los controles tal como quedaron en el
código, con la prueba que los sostiene:

| Control | Cómo se cumple | Prueba |
|---|---|---|
| Audio nunca persistido | El audio no cruza a Dart: el puente transporta texto y estados. No hay archivos temporales | Guardas: el subsistema no puede importar `dart:io`, `path_provider` ni escribir en disco |
| Transcripción efímera | Vive en la memoria de la sesión y muere con la pantalla; `Descartar` la borra y libera el micrófono | Sesión y pantalla |
| Logs sin contenido | Sólo códigos de estado, códigos de error y longitudes. `toString()` de eventos y sesión no imprime lo dictado | Pruebas de privacidad en puerto y sesión |
| Cero escrituras de negocio | El subsistema no puede nombrar repositorios, SQLite, compras, aplicaciones ni pagos | Guardas arquitectónicas que leen los archivos |
| Permiso mínimo y contextual | Sólo `RECORD_AUDIO`, pedido al tocar el micrófono | Guarda sobre el manifiesto: lista exacta de permisos |
| Sin red | **La build de release no declara `INTERNET`**, verificado con `aapt2 dump permissions` sobre el APK. Los manifiestos `debug`/`profile` de la plantilla de Flutter sí lo declaran, para hot reload; no se distribuyen y son anteriores a `EVO-009` | Guardas sobre los tres manifiestos |
| Micrófono liberado | Detener, descartar, entregar, segundo plano, bloqueo, interrupción, `dispose` y salida de pantalla lo sueltan; el lado nativo lo repite en `onPause` por si el proceso se congela | Sesión, pantalla y contrato del puerto |
| Sin escucha permanente | No hay palabra de activación ni servicio en segundo plano. La continuidad sólo reabre el turno mientras el usuario mantiene la sesión, con tope de reintentos y de duración | Sesión, con `fake_async` |
| No prometer offline | Se muestran por separado preferencia pedida, modo avión del sistema, transcripción sin red **observada**, disponibilidad no consultable y modelo posiblemente ausente | Pantalla |
| No prometer `es-BO` | Se pide `es-BO` y se muestra el idioma aceptado; lista de fallback documentada y probada | Política de idioma y pantalla |
| Ingreso manual siempre | El campo editable funciona con permiso denegado, sin idioma y sin reconocedor | Pantalla |

Lo que **no** cubre ninguna de esas pruebas: qué hace el servicio de
reconocimiento del propio Android con el audio. Queda fuera del control de la
aplicación, depende del dispositivo y del fabricante, y por eso la pantalla lo
explica al usuario en vez de afirmar que el proceso es local.

La política normativa completa está en
`features/EVOLUTION-3_SECURITY_AND_CONFIRMATION_POLICY.md`. El motor está decidido en
`ADR-002` (`Accepted`), junto con la política productiva que obliga a `EVO-009`.

## Respuesta mínima a incidentes

Registrar versión, dispositivo, exposición posible, backup disponible, contención y
recuperación. No corregir inconsistencias borrando historial.
