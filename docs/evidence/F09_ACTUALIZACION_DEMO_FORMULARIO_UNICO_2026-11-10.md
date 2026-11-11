# F09: actualización de la demostración `.f09` con el formulario único («Completar por voz»)

- **Fecha real:** 2026-11-10, 21:00–21:12 (hora de Bolivia, UTC−4). Instalación a las 21:03:58.
- **Autorización:** Roderich, 2026-11-10 (actualizar `.f09` con la versión unificada verificada). Sin túnel ni cambio de endpoint en este bloque.
- **Dispositivo:** Xiaomi 22101320G (POCO), Android 12, arm64-v8a, serie `cc14247a`.
- **Código compilado:** `d41586b` (rama `feat/f09-voz-formulario-unico`, árbol limpio), el mismo commit de la candidata «AC F09 U» (`.f09c`) que probó Roderich.
- **Datos:** sólo los sintéticos de la DEMO ya presentes en `.f09`. No se dictó nada en `.f09`, no se guardó audio ni transcripciones y las pantallas con voz se leyeron con la lista blanca de `tool/f09_emu/f09emu.py`.

## 1. Comprobación manual exploratoria del autor (candidata)

Roderich probó en el POCO los tres formularios unificados de la candidata «AC F09 U» (`.f09c`, APK `bb53654b…0b77`, código `d41586b`, datos sintéticos de esa instalación). Su informe, el 2026-11-10: «Ya probé los tres formularios unificados en el teléfono y funcionan correctamente. La entrada manual se conserva y la voz está integrada.»

Se registra como **prueba manual exploratoria**: no hay guion ejecutado paso a paso, frases, tiempos ni mediciones registradas de esa comprobación, y no es una evaluación de precisión.

## 2. Commit y diferencias respecto de la última suite aprobada

| | Commit | Resultado |
|---|---|---|
| Última suite completa | `496278c` | 2859 superadas, 3 omitidas, 0 fallidas (`flutter test -j 8`, una ejecución, 2026-11-10 19:33); `flutter analyze` sin avisos |
| Candidata probada e instalada | `d41586b` | `git diff --stat 496278c d41586b`: sólo `docs/f09/FORMULARIO_UNICO_VOZ_2026-11-10.md` (+76). Se reutiliza la evidencia de la suite. |

Desde `5665496` (código ya instalado en `.f09` hasta hoy, `9d2fb1a` + documentación) no cambian `lib/data/`, `android/`, `pubspec.yaml` ni `pubspec.lock`: esquema de base 14 en ambas versiones.

### Cantidad de pruebas: 2940 → 2859

La suite aprobada anterior (`025c2ef`, idéntica en código y pruebas a `5665496`) tenía 2940 superadas y 3 omitidas. La diferencia (−81) se debe sólo a los archivos de prueba retirados con las pantallas de voz aparte y a los nuevos del formulario único. Cada lado se contó con `flutter test --reporter json` sobre los archivos afectados:

| Archivos | Pruebas |
|---|---|
| 16 archivos retirados (en `5665496`) | −125 |
| 5 archivos nuevos (`form_merge` 15, `compra_formulario_unico` 12, `plan_formulario_unico` 5, `aplicacion_formulario_unico` 5, `formulario_unico_accesos` 7) | +44 |
| `voice_evidence_wiring_test.dart` (portado al formulario) | 4 → 4 |
| **Total** | 2940 − 125 + 44 = **2859** |

Retirados, por archivo (pruebas): `voice_draft_exit` 18, `otra_propuesta` 26, `otra_propuesta_pantalla` 4, `integracion_pantallas_poco` 10, `voice_purchase_draft_screen` 10, `voice_application_draft_screen` 8, `voice_purchase_complete` 7, `ui_application_presentation` 7, `voice_application_plan_ux` 6, `ui_plan_presentation` 5, `voice_plan_draft_screen` 5, `voice_wiring` 5, `compra_formas_pantalla` 4, `compra_precio_total_pantalla` 4, `ui_purchase_presentation` 3, `voice_draft_back_arrow` 3.

Probaban pantallas que ya no existen: los tres borradores de voz, su flecha de volver y su salida, y «Usar la otra propuesta», retirada con la pantalla de compra por frases. Lo que sigue vigente se cubre ahora dentro de los formularios:
- los casos del POCO P1–P4;
- la liberación del micrófono al salir;
- la evidencia con y sin consentimiento;
- el registro único.

Las pruebas de los intérpretes y del dominio no cambiaron. No se añadieron pruebas para recuperar el número.

## 3. APK

| | Anterior (se conserva) | Instalada |
|---|---|---|
| Código | `9d2fb1a` | `d41586b` |
| SHA-256 | `3614a0260c707e10cad75f84737aea1db84fc691eac5c2f6481cae70df842fe4` (333 200 900 B) | `15dabdf2e1a63ef0675ffe54bdfea0a079ac4c3bd4640c654d7280ea60178d9f` (332 938 788 B) |
| Paquete / etiqueta | `com.comunidad.agro.agroquimicos.f09` «AC F09» | igual |
| versionCode / versionName | 2001 / 1.0.0 | igual |
| Firmante (SHA-256 del certificado) | `dd55ce96…c3dc` (Android Debug) | igual |
| Opciones | `AGRO_VOICE_EVIDENCE=true`, sin `AGRO_VOICE_DIAG` | igual |
| Endpoint compilado | origen del túnel de la actualización anterior | **el mismo** (1 aparición en `libapp.so` de ambas; 0 en el registro de compilación; no se imprime) |
| Modelos | Vosk small-es 0.42, whisper-base-q5_1, whisper-small-q5_1 | igual |

Respecto de la candidata probada (`bb53654b…`, `.f09c`), la APK instalada sólo difiere en `AndroidManifest.xml` y `resources.arsc` (sufijo de paquete y etiqueta). El resto de entradas tiene el mismo CRC: `libapp.so` (código Dart), `classes.dex`, bibliotecas nativas y modelos.

Ubicación duradera (fuera de carpetas temporales y de git), con `SHA256SUMS`: `ProyectoAgro/_artefactos/f09/`
- `apk_actual_9d2fb1a/`: APK anterior;
- `apk_nueva_d41586b/`: APK instalada y su registro de compilación;
- `apk_candidata_f09u_d41586b/`: candidata probada;
- `actualizacion_f09_unificada_2026-11-10/{antes,despues_instalar,final}/`: copias para inspección y resúmenes.

## 4. Comandos (resumen)

```bash
F09_REPO=<_wt/F09-UNI> AGRO_API_BASE_URL="$(cat …/origin)" bash build_f09_pres_apk.sh arm64 <_artefactos/f09/apk_nueva_d41586b>
adb shell am force-stop com.comunidad.agro.agroquimicos.f09
F09_SERIAL=cc14247a bash tool/f09_emu/respaldo_pkg.sh com.comunidad.agro.agroquimicos.f09 <antes>
adb push <apk> /data/local/tmp/f09_pres.apk && adb shell pm install -r /data/local/tmp/f09_pres.apk
F09_SERIAL=cc14247a bash tool/f09_emu/respaldo_pkg.sh com.comunidad.agro.agroquimicos.f09 <despues_instalar>
# recorrido por la interfaz con guarda de primer plano; lectura con f09emu.py (lista blanca en pantallas con voz)
F09_SERIAL=cc14247a bash tool/f09_emu/respaldo_pkg.sh com.comunidad.agro.agroquimicos.f09 <final>
```

`origin` es el archivo del origen del túnel anterior (no se abrió túnel). El primer intento de instalación lo abortó la guarda del script antes de tocar el teléfono: `aapt` no aceptó la ruta POSIX. Se repitió con la ruta de Windows.

## 5. Antes de instalar

- `.f09` cerrada con `am force-stop`, sin proceso.
- Copia **para inspección**, que no es un respaldo de restauración probado: dos pasadas coincidentes en el primer intento, sin diario pendiente, integridad `ok`, `user_version` 14.
- Base `agroquimicos_v2.db` SHA-256 `3d64866e…2c39`: la misma, byte a byte, que al terminar la actualización anterior (18:18).
- Negocio, idéntico al resumen ampliado previo a esa actualización:
  - compras 4 (4 985,00 Bs, 0 revertidas), líneas 5, lotes 7, movimientos 11;
  - cuentas: 6 movimientos;
  - pagos a proveedor 2 (3 000,00 Bs);
  - aplicaciones 3, planes 1 (`PLANNED`), transferencias 1.
- Vínculo y ajustes:
  - vínculo del titular activo;
  - ajustes `activated_installation_ref`, `install_origin = NEW_UNDER_POLICY`;
  - cola de envíos vacía;
  - consentimiento de voz 0, evidencia 0.
- Huella del contenido de las 39 tablas y SHA-256 de los 6 archivos de `shared_prefs` (valores cifrados por el Keystore) registrados.

## 6. Instalación

`pm install -r`: `Success`, 21:03:58, sin diálogo de MIUI. `firstInstallTime` se conserva (2026-11-08 17:03:41).
- No se desinstaló, no se borró almacenamiento y no se copiaron datos de `.f09c` ni de `.f09w`.
- Sus APK no cambiaron: `.f09c` `bb53654b…`, `.f09w` `4770e821…`.

## 7. Después

| Comprobación | Resultado |
|---|---|
| Versión instalada | SHA-256 `15dabdf2…8d9f`, versionCode 2001 |
| Justo tras instalar (sin abrir la app) | `datos.tar` idéntico byte a byte al de antes (base, `shared_prefs`, registro) |
| Inicio | «Cuenta vinculada en este dispositivo»; campaña activa Invierno 2026 (DEMO); compras 4 985,00 Bs; pagado 3 000,00 Bs; familias 520,00; terceros 210,00; pagos recibidos 350,00 Bs |
| Compra | Inicio › «Registrar compra»: «Nueva compra», «Paso 1 de 2 · Proveedor y productos», botón «Completar por voz»; al pulsarlo, panel «Listo para dictar» con «Hablar» (no pulsado). También se abrió por Operaciones › Compras › «Nueva compra» (mismo formulario con «Completar por voz») |
| Aplicación | Inicio › «Registrar aplicación»: «Nueva aplicación», «Paso 1 de 3 · Persona y chaco», «Completar por voz»; panel «Listo para dictar». También por Operaciones › Aplicaciones › «Registrar» (mismo formulario) |
| Planificación | Operaciones › Planificación › «Nuevo plan»: «Nueva planificación», «Completar por voz»; panel «Listo para dictar» |
| Diagnóstico | 0 elementos técnicos (modelo, haz, política, métricas, propuestas) en los tres paneles |
| Motores (registro de la app, sin abrir el micrófono) | compra: `voz turno: variante=small disponible=si`; aplicación y planificación: `voz local: segunda pasada review-ok` (revisión con Whisper base). Haz 5: sin cambios de código desde la prueba `9ab203f`, que comprueba que la compra envía `beamSize` 5 al canal nativo |
| Salir sin cambios | compra y aplicación, sin diálogo |
| Salir y descartar | edición manual sin guardar (compra: una línea añadida; aplicación: persona; plan: chaco) → «¿Descartar cambios?» → «Descartar cambios»; las listas siguen con 4 compras, 3 aplicaciones y 1 plan pendiente |
| Final (app cerrada) | base idéntica byte a byte (`3d64866e…`); resumen de las 39 tablas, existencias, saldos, cola, vínculo, ajustes y evidencia idénticos; `shared_prefs` idénticos. Sólo cambia el registro de la app (+6 líneas: inicio, vinculación y disponibilidad de los motores) y la fecha de `files/profileInstalled` |

No se registraron compras, aplicaciones ni planes; no se pulsó «Hablar», «Verificar acceso en línea» ni «Enviar al sindicato».

## 8. Endpoint (disponibilidad, aparte)

- La APK instalada lleva el mismo origen que la anterior: el túnel rápido abierto para la actualización de las 18:10.
- Ese túnel está **cerrado** (0 procesos `cloudflared`). En este bloque no se abrió túnel ni se cambió el endpoint.
- El Central de la DEMO sigue en marcha localmente: `GET http://127.0.0.1:3330/api/v1/health` → 200; contenedor `agro_demo_pg` activo y volumen `agro_demo_pgdata` conservado.
- Consecuencia: `.f09` funciona sin conexión (formularios, voz local), pero sus funciones conectadas necesitan un endpoint disponible: verificar acceso, sincronizar y estimación en línea.
- Un túnel rápido nuevo tendría otro origen y exigiría recompilar con él, como en las actualizaciones anteriores, con autorización aparte.

## 9. Limitaciones

- La comprobación del autor es exploratoria (§1). La de este documento sólo abre los formularios, muestra el panel y descarta: no dicta.
- La copia para inspección no es un respaldo recuperable; restaurar no está probado.
- La suite de `496278c` se ejecutó una vez.
- Sigue abierto, sin explicar: el fallo intermitente de la prueba de estimación «sin copia» (`f12_est_07`).
- Siguen los pendientes declarados en `docs/f09/FORMULARIO_UNICO_VOZ_2026-11-10.md` §8.
