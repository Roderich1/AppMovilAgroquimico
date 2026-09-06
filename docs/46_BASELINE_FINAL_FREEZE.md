# 46 — Congelación de la baseline `v1.0.0-base-stable`

Cierre definitivo del **proyecto base** de Agrocuentas. Este documento no describe una fase
más: describe el estado en el que la baseline se congela y a partir del cual empieza la
evolución funcional.

No sustituye a [`45_UI_AUDIT_FINAL_VERIFICATION`](45_UI_AUDIT_FINAL_VERIFICATION.md), que
sigue siendo el cierre de la fase anterior y se conserva íntegro.

Fecha: **2026-09-06** · Rama de trabajo: `hardening/final-polish` · PR **#4**

---

## 1. Baseline

| | |
|---|---|
| Commit de partida | `c36e5b76bddda426e8bb9f00944f093879f3548f` (`origin/main`, PR #3 integrado) |
| Rama de la fase | `hardening/final-polish` (7 commits) |
| Fecha de cierre | 2026-09-06 |
| Flutter | **3.47.2** · canal `stable` · revisión `d3b14c8769` |
| Dart | **3.13.2** |
| Android de prueba | **16 (API 36)** · AVD `Pixel_8` (`emulator-5554`, `sdk_gphone16k_x86_64`) |
| Pantalla de prueba | 1080 × 2400 px · 420 dpi (densidad 2,625 → 411 × 914 dp) |
| Versión de esquema SQLite | **6** (era 5) |
| Formato de respaldo | **1** (`.agrobackup`) |
| `version:` de `pubspec.yaml` | `1.0.0+1` |

La historia no se reescribió: sin `push --force`, sin `reset --hard`, sin mover ningún tag.

## 2. Estado funcional

Las 17 rutas operan y ninguna queda sin salida. Los flujos contables —compra, asignación,
aplicación, transferencia, pago, reversión, liquidación— funcionan y sus cifras concuerdan
entre listas, detalles y reportes.

Dos reglas de producto que estaban sin decidir quedan decididas, implementadas y protegidas
en el dominio: el **plan de un solo uso** (§7) y la **campaña cerrada terminal** (§8). El
respaldo dejó de ser sólo la base de datos: ahora incluye las fotografías de factura (§9).

## 3. Estado de los UIBUG

| Estado | Nº |
|---|---:|
| `VERIFIED` (corregido y comprobado en Pixel 8) | **67** |
| `FIXED_NOT_DEVICE_VERIFIED` | **1** — `015`, con motivo escrito |
| `WONT_FIX` justificado | **1** — `058` |
| `OPEN` | **0** |
| `IN_PROGRESS` | **0** |
| `DESIGN_DECISION_REQUIRED` | **0** |
| **Total** | **69** |

Por severidad: **CRITICAL 0 abiertos · HIGH 0 · MEDIUM 0 · LOW 0**, salvo el `WONT_FIX`.

### Cerrados en esta fase

| UIBUG | Qué se cerró |
|---|---|
| **023** | La tabla de Inicio ya no pierde el nombre del producto: por debajo de 560 px es una lista con el nombre por encabezado y cada cifra rotulada, sin desplazamiento horizontal |
| **031** | Los cuatro diálogos de catálogo son `Form` con `validator`: el error aparece bajo el campo que falta y no se escribe nada |
| **037** | Sin producto elegido no se pinta `Precio BOB/` ni `Costo 0,00 Bs /`; al elegirlo se vuelve a la forma corta con unidad |
| **038** | El campo de cantidad de la asignación se llama "Cantidad" y lleva su unidad; el de la línea pasa a "Cantidad comprada" para no repetir etiqueta |
| **039** | Una línea sólo dice "Asignado" con cantidad, personas y suma completas; si no, declara qué falta. La regla contable no cambió |
| **040** | Proveedor/campaña y cantidad/moneda se apilan por debajo de 420 px en vez de comprimirse hasta recortar el texto |
| **041** | La tarjeta de línea reserva relleno superior: se corrigió el contenedor, no la posición de un texto concreto |
| **047** | `/catalogos` tiene una sola acción primaria, que además dice qué crea. El FAB global no ofrecía ninguna creación de catálogo, así que retirarlo no quita nada |
| **060** | Sin origen elegido no hay ningún `0`: se explica qué falta y no aparecen controles de cantidad |
| **045** | Decisión de producto tomada e implementada (§7) |
| **059** | Decisión de producto tomada e implementada (§8) |

### Los 16 `FIXED_NOT_DEVICE_VERIFIED` heredados

**15 de 16 se comprobaron en el Pixel 8** durante esta fase: 032, 033, 034, 036, 042, 043,
044, 046, 048, 050, 053, 055, 056, 063 y 064.

El decimosexto, **015**, no es verificable en dispositivo: reproducirlo exigiría corromper la
base mientras la aplicación la tiene abierta, es decir **fabricar una avería en vez de
ejercitar el producto**. Queda cubierto por `error_states_test.dart`, y la causa que lo hacía
visible —`export()` fallando siempre en Android— es UIBUG-001, que sí está verificado en
dispositivo. El detalle está en [`43`](43_UIBUG_FIX_TRACEABILITY.md).

### Encontrados durante esta fase

| UIBUG | Hallazgo |
|---|---|
| **066** | `setState() callback argument returned a Future` en cinco pantallas. Estaba anotado al margen del backlog; ahora tiene ficha, causa, corrección y test |
| **067** | La cinta "Campaña activa" desbordaba la fila con un nombre largo (`RenderFlex overflowed by 84 pixels`). Lo destapó el test de 023 |
| **068** | En horizontal **y** al 130 % el rail de navegación desbordaba 90 px y dejaba "Personas" y "Cuentas" inalcanzables. Latente desde el arreglo de 063: las auditorías anteriores probaron horizontal y 130 % por separado, nunca juntos |

Además se corrigieron **dos regresiones de la propia fase**, antes de cerrarla: Planificación no
recargaba al volver del formulario de aplicación, y la etiqueta "Cantidad comprada" se recortaba
al compartir fila con "Moneda". Ambas se detectaron en el dispositivo y quedaron cubiertas por
tests que se comprobaron en rojo antes del arreglo.

## 4. Tests

| Métrica | Antes de esta fase | **Ahora** |
|---|---:|---:|
| Tests | 170 | **253** |
| Archivos de test | 25 | **34** |

Suites nuevas:

| Archivo | Qué fija |
|---|---|
| `set_state_contract_test.dart` | UIBUG-066 · dos tests de widget que recargan la pantalla y una guarda estática sobre todo `lib/` |
| `ui_polish_test.dart` | 023, 031, 037, 038, 039, 040, 041, 047, 060, 068 |
| `plan_lifecycle_test.dart` | UIBUG-045 · regla de un solo uso, reversión, lista/histórico, persistencia y migración a v6 |
| `plan_lifecycle_ui_test.dart` | UIBUG-045 en pantalla, incluida la recarga al volver de aplicar |
| `campaign_lifecycle_test.dart` | UIBUG-059 · dominio de la campaña terminal |
| `campaign_lifecycle_ui_test.dart` | UIBUG-059 en pantalla |
| `backup_container_test.dart` | Respaldo 2.0 · 27 tests de formato, corrupción, legacy, ciclo completo y rollback |
| `backup_container_support.dart` | Utilidades de test para inspeccionar el contenedor |

Cada test de reproducción se comprobó **en rojo antes del arreglo**. Los que no pueden
montarse como test de widget —porque el `refresh()` sólo se alcanza tras navegar— quedan
cubiertos por la guarda estática.

## 5. CI

| | |
|---|---|
| Workflow | `.github/workflows/flutter-ci.yml` |
| Disparadores | `pull_request`, `push` a `main`, `workflow_dispatch` |
| Permisos | `contents: read` (mínimo privilegio) |
| Flutter fijado | `3.47.2` · JDK `temurin 17` |
| Caché | de Flutter/pub, en la propia acción |
| Timeout | 30 minutos · `concurrency` con `cancel-in-progress` |
| Pasos | `pub get` → `dart format --set-exit-if-changed` → `flutter analyze` → `flutter test` → `flutter build apk --release` |
| Último resultado conocido | **verde** — run `33999797085` sobre el PR #4, 7 min 18 s |

CI **no** necesita keystore: sin `android/key.properties` la build de release queda sin firmar,
que es justo lo que hay que comprobar aquí. No se sube ningún secreto al workflow.

## 6. Base de datos

Esquema **v6**. La migración v5 → v6 hace tres cosas y **ninguna borra datos del usuario**:

1. unifica el vocabulario de estado de plan (`COMPLETED` → `APPLIED`);
2. repara los planes que la regla anterior devolvía a `PLANNED` al revertir su aplicación: si
   existe una aplicación que los referencia, el plan ya se consumió;
3. impone la invariante en el motor con un índice único parcial
   `idx_application_plan_single_use ON applications(plan_id) WHERE plan_id IS NOT NULL`.

Si encuentra un plan aplicado dos veces —posible con la regla vieja— **conserva las filas**,
deja un índice no único y anota la anomalía en `app_settings`
(`schema_v6_plan_reuse_anomaly`), igual que hizo v5 con sus duplicados.

Comprobado: `schema_equivalence_test.dart` verifica que una base migrada desde v3 queda con
**el mismo esquema** que una creada desde cero, y la migración se ejecutó de verdad en el
Pixel 8 al restaurar un respaldo `.db` de la versión anterior: `user_version` 5 → 6,
`integrity_check ok`, índice creado como único y estados normalizados a 4 `APPLIED` / 1
`PLANNED`.

## 7. Planes — regla de un solo uso

**Decisión del propietario (MODELO A).** Un plan representa **una aplicación planificada**, no
una plantilla reutilizable.

- Nace `PLANNED`. Al registrar su aplicación pasa a `APPLIED` y **no vuelve a poder aplicarse**.
- **Revertir la aplicación no reabre el plan.** Revertir corrige un movimiento que ocurrió de
  verdad; no devuelve la intención al futuro. Reabrirlo en silencio dejaría un plan listo para
  volver a aplicarse sin que nadie lo hubiera pedido, y borraría el rastro de que ya se usó.
  Si hay que ejecutar otra vez la planificación, se crea un plan nuevo.
- La protección **no vive sólo en la interfaz**: `confirmApplication` comprueba dentro de la
  transacción que el plan siga pendiente, mirando estado y existencia de aplicación, y el
  índice único parcial es la segunda barrera por si se llega por otro camino. Un doble toque
  produce **una sola** aplicación.
- La **lista operativa** de Planificación muestra los pendientes. Los aplicados se conservan
  íntegros para trazabilidad y se consultan con un interruptor secundario; en el histórico se
  marcan "Aplicado" y no ofrecen la acción.

## 8. Campañas — cierre terminal

**Decisión del propietario.** El ciclo es monótono en operación normal: una campaña `CLOSED`
representa un periodo contable ya rendido y **no puede volver a activarse desde la
aplicación**.

- `activateCampaign` rechaza `CLOSED`, igual que ya rechazaba `ARCHIVED`. Esconder el botón no
  bastaba: la comprobación de dominio cubre también una pantalla desactualizada, una doble
  ejecución y cualquier camino indirecto futuro. La vía de "cerrar la activa y activar otra"
  queda cubierta por la misma barrera.
- Sólo una campaña `PLANNED` ofrece "Activar". La cerrada sólo ofrece "Editar".
- Cerrar es explícito: la confirmación declara la campaña, su periodo, qué deja de admitir y
  que **no podrá reactivarse**, con el botón en color de acción irreversible.
- **No se añadió ninguna reapertura administrativa.** Si algún día hace falta, será una
  funcionalidad explícita y auditable, y no pertenece a esta baseline.

## 9. Respaldo — base **y** fotografías

Perder el teléfono ya no significa perder las facturas.

**Formato:** contenedor `.agrobackup`, que es un **ZIP corriente** —no un formato binario
inventado— con `manifest.json`, `database.db` e `invoices/`. La única dependencia nueva es
`archive`; `crypto` ya venía como transitiva y sólo se promueve a directa para los checksums.

**Manifiesto:** versión de formato, versión de esquema, fecha de creación, versión de la
aplicación, número de fotografías y, por cada una, tamaño, `sha256` y las compras que la
citan. **Nunca un secreto.**

**Compatibilidad hacia atrás:** los respaldos `.db` anteriores se siguen validando y
restaurando. Se reconocen **por su contenido, no por su extensión**, y la aplicación avisa de
que ese formato histórico no trae fotografías y que las del teléfono se conservan. El listado
ofrece los dos formatos.

**Rutas:** la base guarda rutas absolutas del teléfono donde se tomó la foto, así que un
respaldo restaurado en otro dispositivo apuntaría a un directorio inexistente. Al restaurar se
reapunta cada compra a la carpeta local, por nombre de archivo y **sólo** para las fotos que el
respaldo traía: es una reconstrucción acotada, no una migración global de rutas.

**Discrepancias:** si una factura ya no tiene su foto en el teléfono, el respaldo **se completa
igualmente** —bloquearlo dejaría al usuario sin copia de sus cuentas por una foto perdida, que
es peor— pero la pérdida se anota en el manifiesto y se avisa por pantalla. **Nunca en
silencio.** La decisión queda registrada aquí.

**Restauración:** validar → copia de seguridad de base **y** fotografías → cerrar → sustituir →
reubicar fotografías → reabrir (lo que dispara las migraciones) → reapuntar rutas →
comprobación posterior. Ante cualquier fallo se deshace **el conjunto**: nunca queda una base
nueva con las fotos viejas ni al revés.

## 10. Navegación

Atrás es jerárquico y nunca cierra la aplicación con trabajo a medias: comprobado en el
dispositivo con `dumpsys window`, tres niveles seguidos (bitácora → detalle de persona →
Personas → Inicio) mantienen `mCurrentFocus` en la aplicación, y sólo desde Inicio se cede el
gesto al sistema, que es la política elegida en UIBUG-004B.

El FAB global se retira en `/catalogos`, donde ya existe una acción primaria que dice qué crea.
No se pierde ningún destino: los cinco atajos del FAB siguen en Operaciones y en la barra
inferior.

## 11. Pixel 8 — 17 / 17

Regresión completa sobre el entorno conocido (Android 16 / API 36 · 1080×2400 · fuente 1.0 ·
vertical), con RESET → SEED → AUDIT y el dataset determinista de
[`36`](36_UI_AUDIT_DATASET.md), regenerado en esquema v6: 7 personas · 22 productos · 8 chacos
· 4 proveedores · 3 campañas · 10 compras · 7 transferencias · 12 aplicaciones · 5 planes.

| # | Ruta | Resultado |
|---|---|---|
| UI-01 | `/` | ✅ inventario en tarjetas, sin scroll horizontal; la última fila queda sobre el FAB |
| UI-02 | `/operaciones` | ✅ cinco tarjetas que nombran su destino |
| UI-03 | `/catalogos` | ✅ sin FAB, acción primaria por sección, validación visible, campañas con estado y fechas |
| UI-04 | `/planificacion` | ✅ pendientes en la lista, histórico bajo interruptor, "Aplicado" marcado |
| UI-05 | `/planificacion/nueva` | ✅ validación por condición; elegir + «+» agrega con su resumen |
| UI-06 | `/compras` | ✅ historial, visor de factura, pago a proveedor, reversión |
| UI-07 | `/compras/nueva` | ✅ etiquetas con unidad, campos sin comprimir, TOTAL COMPRA despejado |
| UI-08 | `/aplicaciones` | ✅ "Revertida" marcada; reversión con confirmación |
| UI-09 | `/aplicaciones/nueva` | ✅ elegir agrega y despliega; stock negativo en rojo |
| UI-10 | `/liquidacion` | ✅ alcance del saldo declarado; respaldo y restauración |
| UI-11 | `/inventario` | ✅ listado y búsqueda |
| UI-12 | `/inventario/:id` | ✅ alcanzable, con retorno y trazabilidad FIFO |
| UI-13 | `/personas` | ✅ buscador y recarga |
| UI-14 | `/personas/:id` | ✅ pestañas alcanzables, saldo con alcance, retorno |
| UI-15 | `/chacos/:id` | ✅ FIFO legible, fechas locales, barra resalta Personas |
| UI-16 | `/transferencias` | ✅ fecha por movimiento |
| UI-17 | `/transferencias/nueva` | ✅ estado vacío sin origen; 8 productos legibles con origen |

**Flujos reejecutados:** buscar productos · registrar compra · historial · foto de factura ·
pago a proveedor · reversión de aplicación · plan nuevo · aplicar plan · **intentar reaplicar**
· registrar aplicación · transferencia · registrar pago · estado de cuenta · cerrar campaña ·
**intentar reactivar una cerrada** · inventario · persona · bitácora · **respaldo nuevo con
fotos** · **restauración** · **restauración de un `.db` legado** · Atrás jerárquico · Atrás en
raíz · teclado · scroll · fuente 130 % · horizontal · interacción rápida.

**`logcat` al terminar: 0 `RenderFlex`/desbordamientos · 0 avisos de `setState` · 0 errores
mostrados al usuario.**

Evidencia: 60 capturas en `artifacts/ui-audit/fixed/final-freeze/`. Las 119 originales de la
auditoría y las de las fases anteriores siguen intactas.

Ajustes del dispositivo restaurados al terminar: `font_scale 1.0`, `user_rotation 0`,
`accelerometer_rotation 1`.

## 12. Accesibilidad

A **130 %** los nombres truncan con elipsis y no se parten a mitad de palabra; las cifras
contables se leen completas (`19.359,50 Bs`, `14.530,00 Bs`); las columnas no se solapan. El
inventario de Inicio reflota sus cifras a una segunda línea en vez de recortarlas — es
exactamente la ventaja de haber cambiado la tabla por tarjetas.

En **horizontal** el rail muestra las etiquetas de los cinco destinos y, al 130 %, **se
desplaza** para que ninguno quede inalcanzable (UIBUG-068).

**Compromiso deliberado y documentado, sin cambios:** las etiquetas de la barra inferior se
mantienen en su cuerpo base (`MediaQuery.withClampedTextScaling(maxScaleFactor: 1)`). Con cinco
destinos en 1080 px, "Operaciones" no cabe en una línea por encima del 100 %, y la barra sólo
tiene ~90 px de alto, así que no hay sitio donde desplazar. Cada destino lleva icono y **el
resto de la aplicación sí escala**. El rail, que sí tiene sitio, no acota nada.

## 13. Build

| Artefacto | Resultado |
|---|---|
| `flutter build apk --release` | ✅ **60,6 MB**, sin firmar |
| `flutter build appbundle --release` | ✅ **58,6 MB**, sin firmar |
| `dart format --output=none --set-exit-if-changed lib test` | ✅ 0 cambios |
| `flutter analyze` | ✅ **0 issues** |
| `flutter test` | ✅ **253 / 253** |

## 14. Firma para distribución

**No existe keystore.** `android/app/build.gradle.kts` lee las credenciales de
`android/key.properties`, que **no está versionado** (como tampoco `*.jks` ni `*.keystore`), y
sin él la build de release queda deliberadamente **sin firmar**, avisando por consola.

Esto **no** bloquea `READY FOR EVOLUTION`: no falta código ni pruebas, falta una clave privada
que sólo el propietario puede generar y custodiar. Sí bloquea la distribución en Play Store.
Ver [`35_RELEASE_READINESS`](35_RELEASE_READINESS.md), que separa los dos gates.

## 15. Limitaciones conocidas y aceptadas

Sólo lo que de verdad se acepta como está. **Ninguna de estas es un defecto pendiente.**

1. **Sin keystore de release** (§14). Decisión del propietario, no del código.
2. **Escala de texto acotada en la barra inferior** (§12). Compromiso razonado; el resto de la
   aplicación escala.
3. **`UIBUG-058` `WONT_FIX`**: el signo del asiento es contablemente correcto. Invertirlo para
   que "se lea mejor" contradiría el modelo de cuentas.
4. **`UIBUG-015` sin verificación en dispositivo** (§3). Reproducirlo exigiría fabricar una
   avería; está cubierto por la suite.
5. **`appVersion` del manifiesto de respaldo se mantiene a mano** junto a `version:` de
   `pubspec.yaml`. Leerla en ejecución exigiría una dependencia más para un dato puramente
   informativo.
6. **Aplicación monodispositivo y sin red**: no hay sincronización, cuentas ni nube. Es el
   alcance del producto, no una carencia.
7. **El respaldo se escribe en la carpeta de la aplicación** (en Android,
   `Android/data/<paquete>/files/Download`). Sobrevive a un borrado de datos de la aplicación
   pero **no** a desinstalarla: para conservarlo hay que copiarlo fuera del teléfono.

## 16. Evolución diferida

Sólo funcionalidades futuras. **Aquí no hay ningún defecto.**

- Reapertura administrativa de una campaña cerrada, si alguna vez hace falta: como
  funcionalidad explícita y auditable, con su propia traza.
- Duplicar un plan aplicado como punto de partida de uno nuevo (atajo de conveniencia; la
  regla de un solo uso no cambia).
- Compartir el respaldo con el selector del sistema, para llevarlo fuera del teléfono sin cable.
- Purga o archivado opcional de fotografías antiguas, con su efecto sobre el tamaño del
  respaldo.
- Migración progresiva a modelos tipados en lugar de `Map<String, Object?>`, y división de
  `AgroRepository` por áreas. **Deliberadamente fuera de esta fase**: la meta era cerrar la
  baseline, no reabrir la arquitectura.
- Informes exportables (PDF/CSV).

## 17. Veredicto final

> ### `READY FOR EVOLUTION`
>
> La baseline es **funcional, consistente, pulida, recuperable, testeada, documentada,
> trazable y automáticamente verificable**:
>
> - 0 CRITICAL · 0 HIGH · 0 MEDIUM · 0 LOW abiertos; 1 `WONT_FIX` justificado.
> - 0 `DESIGN_DECISION_REQUIRED`: las siete decisiones están tomadas e implementadas.
> - 0 defectos conocidos fuera del backlog: los tres que aparecieron durante la fase tienen
>   ficha, causa, corrección y test.
> - 253 tests en verde · `analyze` 0 issues · formato limpio · APK y AAB de release compilan.
> - CI en GitHub Actions **verde**, reproduciendo los cuatro gates.
> - 17/17 rutas y los flujos críticos comprobados en el Pixel 8, con 60 capturas de evidencia.
> - Respaldo recuperable **con fotografías**, con compatibilidad hacia atrás y rollback
>   demostrados en el dispositivo.
>
> **`READY FOR PRODUCTION DISTRIBUTION`: NO.** Falta el keystore, y sólo el keystore.

## 18. Criterio de congelación

Una vez creado el tag **`v1.0.0-base-stable`** sobre el commit de `main` que integra el PR #4,
esa versión queda **CONGELADA**.

Las funcionalidades futuras **no** se implementan sobre esa baseline histórica: toda evolución
parte de `main` **posterior al tag**, mediante ramas de feature. El tag es el punto exacto de
recuperación.

---

## Documentos relacionados

| Documento | Qué aporta |
|---|---|
| [`41`](41_UIBUG_MASTER_BACKLOG.md) | catálogo de hallazgos: qué se encontró y por qué ocurría |
| [`43`](43_UIBUG_FIX_TRACEABILITY.md) | trazabilidad: cómo se corrigió cada uno y cómo se comprobó |
| [`45`](45_UI_AUDIT_FINAL_VERIFICATION.md) | cierre de la fase anterior (histórico, íntegro) |
| [`35`](35_RELEASE_READINESS.md) | los dos gates de release |
| [`44`](44_NUMERIC_INPUT_SPEC.md) | especificación de la entrada numérica es-BO |
| [`13`](13_LOCAL_STORAGE.md) | formato del respaldo y almacenamiento de fotografías |
| [`15`](15_BUSINESS_RULES.md) | reglas de plan y de campaña |
