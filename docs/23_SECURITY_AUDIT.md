# 23 — Auditoría de seguridad

> Revisión estática del código. **No se modificó nada.**

## Contexto que condiciona toda la valoración

Antes de leer los hallazgos, hay que fijar el modelo de amenaza real:

- La app **no tiene conexión de red** (el permiso `INTERNET` no está en el manifiesto de
  release). No hay superficie de ataque remota.
- **No procesa entradas de terceros**: todos los datos los teclea el propio operador.
- **No hay autenticación**, pero tampoco hay multi-usuario: es una app de un solo operador.
- Los datos son **financieros privados de una familia**, no datos personales de terceros ni
  información regulada.

Esto reduce drásticamente la severidad de lo que en otra aplicación serían hallazgos graves.
Los hallazgos se clasifican **según el impacto real en este contexto**, no según un baremo
genérico.

## Resumen de hallazgos

| ID | Hallazgo | Severidad |
|---|---|---|
| S-01 | La build de release se firma con la clave de depuración | **HIGH** |
| S-02 | Base de datos sin cifrar con toda la información financiera | **MEDIUM** |
| S-03 | Backup sin cifrar escrito fuera del sandbox | **MEDIUM** |
| S-04 | `android:allowBackup` no está desactivado | **MEDIUM** |
| S-05 | Sin control de acceso a la aplicación | **MEDIUM** (depende del contexto) |
| S-06 | Sin trazabilidad de autoría en operaciones financieras | **LOW** |
| S-07 | Nombre de tabla interpolado en `list()` sin lista blanca | **LOW** |
| S-08 | Imágenes de factura sin cifrar y sin limpieza | **LOW** |
| S-09 | Mensajes de error técnicos expuestos al usuario | **LOW** |
| S-10 | `int.parse` sin validar en parámetros de ruta | **LOW** |

### ✅ Verificaciones que resultaron limpias

Estas comprobaciones **no encontraron nada**, y merece la pena dejarlo escrito:

| Comprobación | Resultado |
|---|---|
| **Secretos, claves de API o tokens en el código** | ❌ **Ninguno.** No hay nada que filtrar: la app no habla con ningún servicio |
| **Contraseñas o credenciales hardcodeadas** | ❌ Ninguna |
| **Archivos de configuración con secretos** (`.env`, `google-services.json`) | ❌ No existen |
| **Keystore o certificados en el repositorio** | ❌ Ninguno |
| **Inyección SQL** | ✅ **No explotable.** Todas las consultas usan parámetros posicionales `?`. Ni una sola interpola valores de usuario en la cadena SQL |
| **Tráfico sin cifrar** | ⬜ No aplica: no hay tráfico |
| **WebView insegura** | ⬜ No aplica: no hay WebView |
| **Deserialización insegura** | ⬜ No aplica: no hay serialización |
| **Permisos innecesarios** | ✅ **Ninguno.** El manifiesto de Android no declara ni un solo permiso; iOS declara exactamente los dos que usa, con justificación en español |
| **Logs con datos sensibles** | ✅ **Ninguno.** No hay ni una sentencia de logging en `lib/` |
| **Dependencias con vulnerabilidades conocidas** | ✅ Todas actuales y mantenidas |
| **Código ofuscado o sospechoso** | ✅ Ninguno |

La ausencia total de secretos y de inyección SQL en un proyecto que hace SQL crudo en ~35
consultas es un resultado **muy bueno** y merece reconocimiento explícito.

---

## Hallazgos en detalle

### 🔴 S-01 · HIGH — Release firmada con la clave de depuración

**Ubicación**: `android/app/build.gradle.kts`

```kotlin
buildTypes {
    release {
        // TODO: Add your own signing config for the release build.
        // Signing with the debug keys for now, so `flutter run --release` works.
        signingConfig = signingConfigs.getByName("debug")
    }
}
```

**Impacto**:
- La clave de depuración de Android es **pública y común a todos los SDK instalados**.
  Cualquiera puede compilar un APK con el mismo `applicationId` y la misma firma, y el
  sistema lo aceptará como **actualización legítima** de la app instalada, con acceso a todo
  su directorio de datos.
- Google Play **rechaza** binarios firmados con la clave de depuración: hoy el producto no
  se puede publicar.
- No hay custodia ni rotación de una clave real.

**Severidad**: HIGH si el APK se distribuye de cualquier forma (incluido enviarlo por
mensajería a familiares). MEDIUM si solo se instala desde el equipo de desarrollo.

**Corrección** (no aplicada): keystore fuera del repositorio + `android/key.properties`
en `.gitignore` + `signingConfigs.create("release")`. Detalle en
[20_BUILD_AND_CONFIGURATION](20_BUILD_AND_CONFIGURATION.md).

---

### 🟠 S-02 · MEDIUM — Base de datos sin cifrar

**Ubicación**: `lib/data/app_database.dart` — SQLite estándar, sin SQLCipher.

**Qué contiene el archivo**: nombres y teléfonos de personas, ubicaciones de chacos, todas
las compras con proveedor e importes, el inventario completo y **la deuda de cada familiar y
tercero**.

**Exposición real**:
- En un dispositivo **sin** root/jailbreak: el sandbox lo protege del resto de apps. Riesgo bajo.
- En un dispositivo **con** root/jailbreak, o con acceso físico y depuración habilitada
  (`adb shell run-as ...`, que funciona en builds depurables — y **todas las builds de este
  proyecto están firmadas en modo debug**, ver S-01): el archivo es legible íntegramente.

**Mitigación posible**: `sqflite_sqlcipher`. Implica gestionar una clave, que a su vez
requiere `flutter_secure_storage`. Es un cambio de alcance medio y **no es obviamente
rentable** para este caso de uso; conviene decidirlo con el contexto del punto S-05.

---

### 🟠 S-03 · MEDIUM — Backup sin cifrar fuera del sandbox

**Ubicación**: `lib/data/agro_repository.dart` → `exportBackup()`

El archivo se copia a `getDownloadsDirectory()`. En Android, **Descargas está fuera del
sandbox**: cualquier aplicación con permiso de almacenamiento, o cualquiera que conecte el
teléfono a un ordenador, puede leer la contabilidad completa.

Agravantes:
- El nombre incluye la marca de tiempo, es predecible y fácil de localizar.
- No se avisa al usuario de que el archivo queda sin protección.
- No se limpian backups antiguos: se acumulan.

**Mitigación de bajo coste**: exportar a través del *share sheet* del sistema (dejando que
el usuario elija el destino) en lugar de escribir directamente en Descargas, y advertir en
el snackbar de que el archivo no está cifrado.

---

### 🟠 S-04 · MEDIUM — `android:allowBackup` sin desactivar

**Ubicación**: `android/app/src/main/AndroidManifest.xml` — el atributo **no se declara**,
por lo que se aplica el valor por defecto de la plataforma (históricamente `true`).

**Impacto**: la base de datos sin cifrar puede incluirse en las copias de seguridad
automáticas de Android (Auto Backup / Google Drive) y, en dispositivos depurables, extraerse
con `adb backup`. Esto **elude el aislamiento del sandbox** que era la principal mitigación
de S-02.

**Corrección de coste mínimo**: añadir `android:allowBackup="false"` y
`android:dataExtractionRules` al elemento `<application>`. Una línea.

> Nota: desactivarlo también significa que el usuario **pierde los datos al cambiar de
> teléfono**. Dado que tampoco hay restauración desde la propia app
> ([14_OFFLINE_AND_SYNC](14_OFFLINE_AND_SYNC.md)), conviene resolver antes la función de
> restauración y decidir las dos cosas juntas.

---

### 🟠 S-05 · MEDIUM — Sin control de acceso

**Ubicación**: todo el proyecto. Ver [12_AUTHENTICATION](12_AUTHENTICATION.md).

Cualquiera que desbloquee el dispositivo tiene acceso total de lectura y escritura, incluida
la capacidad de exportar toda la base.

**La severidad depende enteramente del contexto de uso**, que el código no revela:

| Escenario | Severidad real |
|---|---|
| Un solo dispositivo, en manos del administrador | **LOW** — aceptable |
| Dispositivo compartido entre familiares | **MEDIUM** |
| Dispositivo que sale del entorno familiar | **HIGH** |

`REQUIERE INFORMACIÓN DEL DESARROLLADOR`.

**Mitigación proporcionada** (no login completo): bloqueo opcional por biometría o PIN al
abrir la app, activable por el usuario. Coste bajo con `local_auth`.

---

### 🟡 S-06 · LOW — Sin trazabilidad de autoría

Ninguna tabla registra **quién** creó cada operación. `account_transactions` guarda
`person_id` (a quién afecta), pero no el operador que la introdujo. Lo mismo en `purchases`,
`applications` y `transfers`.

**Impacto**: si varias personas usan el dispositivo, es imposible saber quién registró o
revirtió una operación. En un sistema que maneja deudas entre familiares, esto puede
convertirse en un problema de confianza antes que de seguridad.

**Mitigación**: una columna `created_by` (aunque sea seleccionada manualmente) daría
auditoría **sin necesidad de implementar autenticación**. Es probablemente la mejora de
seguridad con mejor relación coste/beneficio del proyecto.

---

### 🟡 S-07 · LOW — Nombre de tabla interpolado en `list()`

**Ubicación**: `lib/data/agro_repository.dart`

```dart
Future<List<Map<String, Object?>>> list(String table, {String? orderBy}) =>
    _db.then((db) => db.query(table, orderBy: orderBy ?? 'id DESC'));
```

El nombre de tabla y la cláusula `orderBy` se pasan sin validar. Contrasta con
`renameCatalog` y `archiveCatalog`, que **sí** aplican una lista blanca:

```dart
const allowed = {'persons', 'farms', 'products', 'suppliers', 'campaigns'};
if (!allowed.contains(table)) throw ArgumentError('Catálogo no permitido.');
```

**No es explotable hoy**: todas las llamadas a `list()` pasan literales
(`'campaigns'`, `'application_plan_items'`, `'inventory_lots'`, …), la mayoría desde tests.
Ninguna entrada de usuario llega a este método.

**Por qué se registra igualmente**: es una API pública con una firma que invita al mal uso,
en una clase donde el patrón seguro ya existe a pocas líneas de distancia. Aplicar la misma
lista blanca sería coherente y gratuito.

---

### 🟡 S-08 · LOW — Imágenes de factura sin cifrar y sin limpieza

**Ubicación**: `storeInvoiceImage` → `<documentos app>/invoices/`

- Sin cifrar (mismo análisis de exposición que S-02).
- **Nunca se borran**: revertir una compra no elimina su imagen.
- Se generan **huérfanas**: `PurchaseFormScreen._confirm` copia la imagen **antes** de
  llamar a `confirmPurchase`; si la compra falla, el archivo queda sin referencia.
- Pueden contener datos comerciales sensibles (proveedor, importes, identificación fiscal).

---

### 🟡 S-09 · LOW — Errores técnicos expuestos al usuario

`friendlyError` no traduce `DatabaseException`, por lo que el usuario puede ver texto como:

```
DatabaseException(CHECK constraint failed: area_m2 > 0) sql 'INSERT INTO farms ...'
```

**Filtración de información**: nombres de tablas, columnas y restricciones. En una app sin
red y sin adversario remoto el impacto es **mínimo**; se registra por completitud y porque
la corrección mejora además la experiencia de usuario. Ver
[17_ERROR_HANDLING](17_ERROR_HANDLING.md).

---

### 🟡 S-10 · LOW — `int.parse` sin validar en rutas

```dart
GoRoute(path: '/inventario/:id',
  builder: (_, state) => InventoryDetailScreen(
    productId: int.parse(state.pathParameters['id']!)));
```

Igual en `/personas/:id` y `/chacos/:id`. Un id no numérico lanza `FormatException` al
construir la ruta.

**No explotable**: no hay deep links configurados (sin `intent-filter` de `VIEW` ni
`CFBundleURLTypes`), así que no hay forma externa de inyectar una ruta. Es un defecto de
robustez más que de seguridad. Nótese que `/aplicaciones/nueva` **sí** usa `int.tryParse`,
lo que demuestra que el patrón correcto ya se conoce en el proyecto.

---

## Priorización recomendada

| Prioridad | Acción | Coste |
|---|---|---|
| 1 | **S-01**: configurar firma de release real | Bajo |
| 2 | **S-04**: `android:allowBackup="false"` (junto con la función de restauración) | Trivial |
| 3 | **S-06**: columna de autoría en operaciones | Bajo |
| 4 | **S-03**: exportar por *share sheet* y advertir que no está cifrado | Bajo |
| 5 | **S-09**: traducir `DatabaseException` en `friendlyError` | Bajo |
| 6 | **S-07**: lista blanca en `list()` | Trivial |
| 7 | **S-05**: bloqueo opcional por biometría | Medio |
| 8 | **S-02**: cifrado de la base | Medio-alto (decidir según contexto) |
| 9 | **S-08**: limpieza de imágenes huérfanas | Bajo |
| 10 | **S-10**: `tryParse` + ruta de error | Trivial |

## Conclusión

**La postura de seguridad de esta aplicación es mejor de lo que sugiere la ausencia de
autenticación.** No tener red, ni secretos, ni entradas de terceros, ni dependencias de
análisis elimina de golpe la mayoría de las clases de vulnerabilidad habituales. El uso
sistemático de consultas parametrizadas evita la única categoría que sí era plausible dada
la arquitectura.

Los dos problemas que merecen acción inmediata no son de código de aplicación sino de
**configuración de despliegue** (S-01) y de **protección de datos en reposo** (S-03/S-04).

El riesgo dominante del producto **no es de seguridad, sino de disponibilidad**: la pérdida
del dispositivo implica la pérdida total de los datos. Ver
[14_OFFLINE_AND_SYNC](14_OFFLINE_AND_SYNC.md).
