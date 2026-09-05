# 01 — Visión general del proyecto

## Identidad

| Dato | Valor | Fuente |
|---|---|---|
| Nombre del paquete Dart | `agroquimicos` | `pubspec.yaml:1` |
| Nombre comercial en README | **Agrocuentas V2** | `README.md:1` |
| Título en la app | `Agrocuentas` | `lib/app.dart:125` |
| `applicationId` Android | `com.comunidad.agro.agroquimicos` | `android/app/build.gradle.kts:19` |
| Etiqueta Android | `agroquimicos` | `android/app/src/main/AndroidManifest.xml:3` |
| `CFBundleDisplayName` iOS | `Agroquimicos` | `ios/Runner/Info.plist` |
| Versión | `1.0.0+1` | `pubspec.yaml` |
| `description` en pubspec | `"A new Flutter project."` (plantilla sin personalizar) | `pubspec.yaml:2` |

> El naming es inconsistente entre plataformas (`Agrocuentas` / `agroquimicos` / `Agroquimicos`).
> Registrado en [26_TECHNICAL_DEBT](26_TECHNICAL_DEBT.md).

## Qué hace el producto

Aplicación **Flutter offline-first** para que una familia de agricultores administre la
compra, distribución, aplicación y costeo de **agroquímicos** compartidos entre familiares
y terceros. Todo el estado vive en una base **SQLite local**; no hay backend.

El problema de negocio que resuelve, deducido de la implementación:

1. Varias personas compran insumos **juntas en una misma factura**, a veces en dólares.
2. Cada persona recibe una parte de esa compra (*asignación*).
3. Cada persona aplica producto en **sus chacos**, consumiendo su propio stock.
4. Hay que saber **quién debe cuánto**, y ese cálculo depende del tipo de persona:
   - a los **familiares** se les cobra por **consumo real** (lo que efectivamente aplicaron);
   - a los **terceros** se les cobra por **asignación de compra** (lo que se llevaron).
5. Todo debe ser **auditable y reversible** sin borrar historia.

## Actores

Confirmados en `lib/domain/models.dart:1` (`enum PersonRole`) y en el `CHECK` del esquema
(`lib/data/app_database.dart:60`):

| Rol (`persons.role`) | Política de cobro por defecto | Significado operativo |
|---|---|---|
| `ADMIN` | `MANUAL` | Administra el sistema y **paga a los proveedores**. Excluido de liquidaciones (`settlements()` filtra `role<>'ADMIN'`, `agro_repository.dart:1715`) y de los selectores de aplicación/transferencia. |
| `FAMILY` | `BY_ACTUAL_USAGE` | Familiar. Recibir stock **no le genera deuda**; la deuda nace al **aplicar**. |
| `THIRD_PARTY` | `BY_PURCHASE_ALLOCATION` | Tercero. La deuda nace al **confirmarse la compra**, por la cantidad asignada. |

La asignación de la política ocurre en `addPerson` (`agro_repository.dart:40-46`) y puede
sobreescribirse pasando `policy`, aunque **la UI nunca lo hace** (`catalogs_screen.dart:_add`
llama `addPerson(name:, role:)` sin `policy`).

> No existe concepto de "usuario logueado". El operador de la app tiene acceso total.
> Ver [12_AUTHENTICATION](12_AUTHENTICATION.md).

## Alcance funcional confirmado

Presente en el código:

- Catálogos: personas, chacos (`farms`), productos, proveedores, campañas.
- Campañas con la invariante **una sola activa a la vez**.
- Planificación de aplicaciones por chaco y mezcla de productos.
- Compras multiproducto, multi-moneda (BOB/USD) con **tipo de cambio histórico por línea**.
- Foto de factura tomada con cámara o galería, copiada al almacenamiento de la app.
- Pagos a proveedores, separados de las cuentas internas de las personas.
- Inventario por **lotes** y **movimientos**, con costeo **FIFO**.
- Aplicaciones (fumigaciones) multiproducto que consumen stock FIFO.
- Transferencias de stock entre personas, multiproducto, preservando costo histórico.
- Cuentas corrientes: cargos, pagos, adelantos, imputación cronológica de pagos a deudas.
- Reversión de compras, aplicaciones y transferencias con reglas de seguridad.
- Reportes: costo por chaco/hectárea, costo por producto, estado de cuenta cronológico.
- Exportación de backup: copia del archivo `.db`.

Ausente en el código (confirmado por búsqueda exhaustiva):

- Backend, API HTTP, sincronización en la nube — ver [11_API_INTEGRATION](11_API_INTEGRATION.md).
- Login, roles de acceso, cifrado — ver [12_AUTHENTICATION](12_AUTHENTICATION.md) y [23_SECURITY_AUDIT](23_SECURITY_AUDIT.md).
- Notificaciones push o locales — ver [19_NOTIFICATIONS](19_NOTIFICATIONS.md).
- Analytics, crash reporting, logging estructurado.
- Internacionalización: los textos están **hardcodeados en español** y el formateo usa
  `locale: 'es_BO'` fijo (`lib/domain/money.dart:36,43`).

## Plataformas

`android/`, `ios/` y `web/` existen. `.metadata` declara `root`, `android`, `ios`, `web`.

- **Android**: configurado y compilable; el README documenta `flutter build apk --debug`.
- **iOS**: presente, con permisos de cámara/galería declarados. **No hay `Podfile`** en el
  repositorio, por lo que la build de iOS no está verificada aquí.
- **Web**: la carpeta existe, pero `AppDatabase._platformFactory` (`app_database.dart:37-44`)
  **no contempla web**: en `kIsWeb` cae a `mobile.databaseFactory`, que no funciona en navegador.
  Además `dart:io` (`File`, `Directory`, `Platform`) se importa en el repositorio y en dos
  pantallas. **La app no es funcional en web tal como está.**
- **Desktop** (Windows/Linux/macOS): no hay carpetas de plataforma, pero el código **sí**
  contempla escritorio mediante `sqflite_common_ffi` (`app_database.dart:38-43,47-52`).
  Esto se usa hoy sobre todo para que los tests corran con `databaseFactoryFfi`.

## Documentos de especificación previos en la raíz

Existen dos archivos de la fase de diseño:

- `AGROQUIMICOS_IMPLEMENTATION_SPEC_V2.md`
- `CODEX_MASTER_PROMPT_AGROQUIMICOS_V2.md`

Son **documentos de intención, no de estado**. Esta auditoría no los usó como fuente de
verdad: todo lo documentado aquí se verificó contra el código. Si hay divergencias entre
esos specs y estos documentos, **manda el código**.
