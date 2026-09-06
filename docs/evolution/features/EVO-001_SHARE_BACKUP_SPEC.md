# Feature Evolution Spec — EVO-001 Compartir backup validado

## Identity

| Campo | Valor |
|---|---|
| Feature ID | `EVO-001` |
| Owner decision | Diferida el 2026-09-06 por prioridad de EVOLUTION-2/3 |
| Status | `DEFERRED` |
| Recomendación | Conservar la spec y reevaluar después de EVOLUTION-3 |

## Problem

El `.agrobackup` contiene base y fotografías, pero queda en la carpeta externa propia de la
aplicación. Puede sobrevivir al borrado de datos, pero no a una desinstalación y no está fuera
del teléfono hasta que el usuario lo copie por otro medio.

## User Value

El usuario puede guardar o enviar una copia completa y ya validada a un destino elegido, sin
usar cable ni navegar manualmente por carpetas internas.

## Scope

- Exportar con el `BackupService` actual.
- Validar el contenedor recién creado antes de ofrecerlo.
- Entregarlo al mecanismo del sistema mediante una frontera `BackupTransport`.
- Mostrar resultado, advertencias por fotos faltantes y ubicación/destino cuando sea conocido.
- Mantener disponible la copia local ante cancelación o fallo de transporte.

## Non-Scope

- Cloud automático, sync, cuentas, cifrado, programación periódica o cambio de schema.
- Cambiar manifest/formato 1, restore, fotografías o reglas contables.
- Considerar una app receptora como almacenamiento confiable.

## User Flow

1. Usuario pulsa «Crear y compartir respaldo».
2. La app genera y valida `.agrobackup`.
3. Si existen warnings, los presenta antes de continuar.
4. La app abre la UI del sistema para compartir/guardar.
5. Cancelar no se trata como corrupción ni borra la copia local.
6. Éxito muestra nombre, tamaño y fecha; fallo permite reintentar transporte sin regenerar.

## Functional Requirements

| ID | Requisito |
|---|---|
| EVO-001-REQ-01 | Nunca compartir un contenedor que no pase `BackupService.validate`. |
| EVO-001-REQ-02 | La selección del destino pertenece al usuario y a la UI del sistema. |
| EVO-001-REQ-03 | Advertir que el archivo no está cifrado antes de exponerlo. |
| EVO-001-REQ-04 | Cancelación no es error y no cambia datos operativos. |
| EVO-001-REQ-05 | Fallo de transporte no modifica DB, fotos ni backup generado. |
| EVO-001-REQ-06 | Mantener compatibilidad con restore formato 1 y legacy `.db`. |
| EVO-001-REQ-07 | No requerir red para crear/validar; un destino remoto puede requerirla. |

## Business Rules

No modifica roles, cuentas, stock, FIFO, campañas, planes ni reversiones.

## Data Changes

Ninguno. Registrar fecha del último backup pertenece a `EVO-002`.

## Architecture

Introducir un puerto pequeño `BackupTransport` que recibe archivo/metadata y devuelve
`shared`, `cancelled` o fallo tipado. `BackupService` sigue siendo dueño de crear/validar;
presentation coordina mensajes, no filesystem nativo.

La dependencia/plugin se elige durante planificación mediante documentación oficial,
compatibilidad con Flutter 3.47.2/Android API 36, licencia, mantenimiento y testabilidad. No se
fija una versión en esta fase.

## Error Handling and Offline

- Export/validation failure: no abrir transport; mensaje accionable y log local.
- Cancelled: volver utilizable, sin snackbar rojo.
- Recipient unavailable: conservar archivo y permitir reintento.
- Totalmente offline hasta que el usuario elija un destino que dependa de red.

## Security

Riesgo `RISK-009`. Requiere acción explícita, aviso de contenido sensible y no agrega el
backup a logs. No solicita permiso de almacenamiento amplio si el mecanismo del sistema puede
conceder acceso puntual.

## Backup/Migration Impact

Formato `1`, schema `6`, sin migración. Deben restaurarse tanto el archivo local como una copia
devuelta por el flujo de transporte.

## Tests

- Export válido → transport recibe exactamente el archivo validado.
- Warning por foto ausente se conserva.
- Contenedor inválido nunca llega al transport.
- Cancelación y excepción no alteran DB/fotos/archivo.
- Doble toque no lanza dos exportaciones/hojas simultáneas.
- Nombre con fecha y MIME/extensión correctos.
- Fake semántico y prueba Pixel 8 con guardar, compartir, cancelar y receptor ausente.

## Rollback

Retirar UI/adaptador y conservar `BackupService`/formato. No hay downgrade ni restauración de
datos porque no cambia persistencia.

## Acceptance Criteria

- [ ] Un backup compartido vuelve a validar y puede restaurarse con sus fotografías.
- [ ] Cancelar/fallar deja la aplicación y los datos utilizables.
- [ ] No se solicita permiso amplio innecesario.
- [ ] CI y verificación Pixel 8 están enlazados.
- [ ] El usuario ve que el archivo no está cifrado.

## Decisión pendiente al reactivar

Cuando el propietario reactive `EVO-001`, deberá elegir la experiencia primaria: «Compartir»
mediante hoja del sistema o «Guardar copia» mediante selector de documentos. Esta decisión no
bloquea EVOLUTION-2 ni EVOLUTION-3.
