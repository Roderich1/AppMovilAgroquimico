# F09: actualización de la demostración `.f09` con la compra por voz (Whisper small, haz de 5)

- **Fecha real:** 2026-11-10, 18:10–18:30 (hora de Bolivia, UTC−4).
- **Autorización:** Roderich, 2026-11-10 (actualizar `.f09` y reabrir temporalmente el túnel de la DEMO).
- **Dispositivo:** Xiaomi 22101320G (POCO), Android 12, arm64-v8a, serie `cc14247a`.
- **Código compilado:** `9d2fb1a` (rama `feat/f09-compra-voz-small`, árbol limpio). Respecto de la última suite completa aprobada (`025c2ef`: 2940 superadas, 0 fallidas, `-j 8`) sólo cambia documentación; el código de la app (`lib/`, `android/`, dependencias) es idéntico al de la candidata verificada en `.f09c` (`86cbac1`).
- **Datos:** sólo los sintéticos de la DEMO ya presentes en `.f09`; voz **sintética** (Windows, voz Helena, frase de guion) por el altavoz del PC. Sin audio guardado ni transcripciones; las pantallas de voz se leyeron con la lista blanca `tool/f09_emu/f09emu.sh voz`.

## APK

| | Anterior (se conserva) | Instalada |
|---|---|---|
| Código | `71e55fc`, de diagnóstico | `9d2fb1a`, presentación |
| Archivo | `%LOCALAPPDATA%/Temp/agro_f09/apk_diag_71e55fc/agrocuentas-f09diag-71e55fc-arm64-v8a-profile.apk` | `%LOCALAPPDATA%/Temp/agro_f09/apk_f09_pres_9d2fb1a/agrocuentas-f09-pres-9d2fb1a-arm64-v8a-profile.apk` |
| SHA-256 | `8a323bd1881417e0d094cb3f073e5dfcd88c1abf30c0244071eb09ebc993d849` | `3614a0260c707e10cad75f84737aea1db84fc691eac5c2f6481cae70df842fe4` (333 200 900 B) |
| Paquete / etiqueta | `com.comunidad.agro.agroquimicos.f09` «AC F09» | igual |
| versionCode | 2001 | 2001 |
| Firmante | `dd55ce96…c3dc` (Android Debug) | igual |
| Opciones | `AGRO_VOICE_EVIDENCE=true`, `AGRO_VOICE_DIAG=true` | `AGRO_VOICE_EVIDENCE=true`, **sin** `AGRO_VOICE_DIAG` |
| Esquema de base | 14 | 14 |
| Modelos | Vosk small-es 0.42 + whisper-base-q5_1 | + whisper-small-q5_1; `libagro_whisper.so` con `transcribeWith` |

Dirección del servicio comprobada antes de compilar: túnel nuevo, `GET /api/v1/health` 200 (origen no impreso; 0 apariciones en el registro de compilación).

## Comandos (resumen)

```bash
bash tool/demo/demo-mobile.sh tunnel                       # _wt/DEMO-MOB, autorizado
F09_REPO=<_wt/F09-COMPRA> AGRO_API_BASE_URL="$(cat …/origin)" bash build_f09_pres_apk.sh arm64 <salida>
adb shell am force-stop com.comunidad.agro.agroquimicos.f09
F09_SERIAL=cc14247a bash tool/f09_emu/respaldo_pkg.sh com.comunidad.agro.agroquimicos.f09 <antes>
adb push <apk> /data/local/tmp/f09_pres.apk && adb shell pm install -r /data/local/tmp/f09_pres.apk
F09_SERIAL=cc14247a bash tool/f09_emu/respaldo_pkg.sh com.comunidad.agro.agroquimicos.f09 <después>
bash tool/f09_emu/f09emu.sh voz                            # lectura por lista blanca
bash tool/demo/demo-mobile.sh untunnel
```

## Antes de instalar

- `.f09` sin proceso (cerrada); `am force-stop` para evitar escrituras.
- Copia **para inspección** (no es un respaldo de restauración probado): dos pasadas coincidentes en el primer intento; sin diario pendiente; integridad `ok`; `user_version` 14.
- Negocio: compras 4 (4 985,00 Bs, 0 revertidas), líneas 5, lotes 7, movimientos 11, cuentas 6 movimientos (Beto 520,00 · Carmen 210,00 · Rosa 720,00 Bs), pagos a proveedor 2 (3 000,00 Bs), aplicaciones 3, planes 1 (`PLANNED`), transferencias 1. Existencias: Herbicida DEMO 11 L (Rosa) y 2 L (Beto); Fungicida DEMO 8 L (Rosa) y 4 L (Beto); Insecticida DEMO 4 L (Carmen).
- Vínculo del titular activo; ajustes `activated_installation_ref`, `install_origin = NEW_UNDER_POLICY`; cola de envíos **vacía**; consentimiento de voz 0, evidencia 0.
- Huella SHA-256 del contenido de cada una de las 39 tablas registrada.

## Instalación

`pm install -r`: `Success` 18:18:00, sin diálogo de MIUI; `firstInstallTime` se conserva (2026-11-08 17:03:41). No se desinstaló, no se borró almacenamiento, no se copiaron datos de `.f09c` ni `.f09w` (sus APK no cambiaron).

## Después

| Comprobación | Resultado |
|---|---|
| Versión instalada | SHA-256 `3614a026…42fe4`, versionCode 2001 |
| Datos justo tras instalar | base **idéntica byte a byte** (356 352 B, SHA-256 `3d64866e…2c39`); resumen de las 39 tablas idéntico |
| Vinculación y acceso | Inicio: «Cuenta vinculada en este dispositivo»; campaña activa Invierno 2026 (DEMO); compras 4 985,00 Bs; pagado 3 000,00 Bs |
| Compra por voz | «Reconocedor: modelo de voz de la aplicación (whisper-small-q5_1)»; registro de la app: `variante=small modelo=whisper-small-q5_1 haz=5` |
| Diagnóstico | 0 controles de diagnóstico en «Registrar por voz» y en toda la pantalla de compra; tampoco visibles en planificación y aplicación |
| Aplicación y planificación | «Reconocedor: … (vosk-model-small-es-0.42)», «Revisión de cada frase: whisper-base-q5_1» |
| Borrador (frase sintética) | Producto 1 «Herbicida DEMO» (catálogo) Dictado · Cantidad 2 L Dictado · Precio 50 por L Dictado · Moneda BOB Dictado; campaña Propuesto; faltan proveedor, destinatario y pago → «Registrar compra» deshabilitado |
| Cancelación | «Cancelar» → «Registrar por voz»; resumen de las 39 tablas **idéntico** al de antes (compras, inventario, cuentas, cola, vínculo, ajustes) |
| Transcripción | audio 12 860 ms, inferencia **14 173 ms**, carga del modelo 262 ms (logcat); el borrador estaba listo a los ~15–20 s de «Terminar» (lectura de pantalla cada ~4 s) |
| Acceso en línea | cola vacía comprobada antes; «Verificar acceso en línea» → «Acceso en línea verificado para esta sesión.»; por el túnel sólo `POST /api/v1/auth/v2/refresh 200`; en los ~1,5 min siguientes, ninguna otra llamada (nada pendiente que enviar). No se pulsó «Enviar al sindicato» |
| Final | nueva copia: resumen de las 39 tablas idéntico al de antes; túnel cerrado (0 procesos `cloudflared`); contenedor `agro_demo_pg` y volumen `agro_demo_pgdata` conservados |

## Limitaciones

- La copia para inspección no es un respaldo recuperable; restaurar no está probado. La vuelta al APK anterior se probó sólo en `.f09c` (`docs/f09/INTEGRACION_COMPRA_VOZ_SMALL_2026-11-10.md` §7.3).
- Con el túnel cerrado, `.f09` funciona sin conexión pero sus funciones conectadas (verificar acceso, sincronizar, estimación en línea) necesitarán un endpoint disponible en la presentación; con un túnel rápido nuevo habría que recompilar con ese origen.
- Una sola frase sintética: no es una evaluación de precisión.
- Sigue abierto, sin explicar: el fallo intermitente de la prueba de estimación «sin copia» (`f12_est_07`, línea 193).
- Pendientes del autor: holdout, consentimiento v2, #17 (Pending) y #12 (sin ejecutar).
