# Cierre Mobile (2026-11-13)

Resumen completo del cierre (las dos partes, PR, recorridos, matriz para el documento de grado): `Roderich1/Agro_Sindicato_Backend-Web`, `docs/cierre/RESUMEN_CIERRE_2026-11-13.md`, con la evidencia en `docs/evidence/CIERRE/`. Aquí, lo propio de la app.

## Rama y composición

- PR [#192](https://github.com/Roderich1/AppMovilAgroquimico/pull/192), rama `integracion/cierre-mob`; código final probado `aeeb4f0`.
- Composición por ascendencia: UXJ → F09 voz → E1/E2 → rediseño móvil (`507efc8`) → E4 estable (`f9aac3a`; `9da5054` descartada) + modo individual (`bfe0fa2`, código `b8248fb`) en `f8de886` → aviso de Inicio en ambos modos (`64e1d7b`) → panel de voz en ambos modos (`1310f9e`) → formato (`db79890`) → exportaciones y sesión caducada (`efd661d`).
- Requiere la API de `integracion/cierre-be` (contrato del agricultor 4): fusionar aquélla **antes**.

## Compatibilidad y actualización

- Esquema SQLite **20** (`AppDatabase.schemaVersion = 20`, `jointPurchaseRoleAccessSinceVersion = 20`). `pubspec`: `1.0.0+1`.
- Actualizar encima conserva los datos: al abrir, 19 → 20 (tabla `joint_purchase_access_ops` y disparador `trg_joint_purchase_access_ops_sequence`). Recorrido M2 en el emulador: 44 → 45 tablas, filas anteriores intactas, sin reactivar.
- La app anterior (`507efc8`, contrato 3) recibe «Actualice la aplicación» en convocatorias.

## Pruebas sobre `aeeb4f0`

| Comprobación | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test` | 0 cambios |
| `flutter analyze` | sin issues |
| `flutter test --concurrency=4` | **3202 pasan, 3 omitidas, 0 fallan** |
| CI GitHub (Flutter CI) | success |

Recorrido en el emulador (AVD `Cierre_Pixel8`, Android 16 x86_64; sin teléfono físico): M1–M7, ver el resumen del Backend §6.

## Decisiones del autor aplicadas

- **A, panel de voz:** misma presentación nueva en los dos modos, con los mismos componentes. No cambian motores, modelos, validaciones, cancelación ni la confirmación humana.
- **B, superficie del chaco:** sin edición en el cierre. Queda como mejora pendiente.
- **C, exportaciones:** en modo individual, «Costo por chaco» y «Costo por producto» llevan el ámbito y los filtros de la pantalla, sin recalcular nada. «Resumen de campaña» es una limitación aceptada: incluye aplicaciones en chacos de terceros.
- **E, sesión caducada:** la app dice que la decisión no se envió, ofrece «Volver a autenticar» y luego «Enviar ahora». Nada figura como aplicado antes del acuse.
- **Ayuda:** no hay pantalla de Ayuda y no se inventó una; es una diferencia con el prototipo.

## Distribución

- La compilación de release del repositorio sale **sin firmar**: no existe `android/key.properties`, y esto es deliberado (ver `docs/20_BUILD_AND_CONFIGURATION.md`). Hace falta la keystore del propietario.
- El origen de la API se compila con `AGRO_API_BASE_URL`, y no hay ninguna API desplegada.
- Los modelos de voz (`android/app/voice-models`) y las bibliotecas nativas de whisper.cpp (`jniLibs/`) no están en Git: se preparan con `tool/voice_local/fetch_voice_models.sh` y `build_whisper_libs.sh`.
- APK final generada desde `main`: ver `_artefactos/cierre/README.md` y el resumen del Backend §9.
