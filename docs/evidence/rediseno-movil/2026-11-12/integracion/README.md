# Rediseño móvil · integración de las sesiones A, B, C y F — evidencia

- **Fecha real:** 2026-11-12 (UTC−4), tarde y noche.
- **Rama / worktree:** `feat/rediseno-movil` en `_wt/RDM-MOB` (rama de integración). Sin push.
- **Commit verificado:** `6b397c9` (suite completa y APK). Coordinación y entregas integradas: `docs/rediseno/COORDINACION.md`.
- **Dispositivo:** emulador **propio** `RDM_Pixel8` (`emulator-5556`, imagen `android-36.1 google_apis_playstore_ps16k x86_64`, datos de 8 GB, arrancado **sin audio**), creado el 2026-11-12 para no depender del espacio del `Pixel_8` compartido. El POCO no estaba disponible.
- **Back:** worktree congelado propio `_wt/RDM-BE` en `5b394f2` (contrato de convocatorias 2 y migración P-C de la rama F), `npm ci` + `prisma generate` + `nest build`; migraciones aplicadas con `prisma migrate deploy` (bootstrap) en el contenedor propio `agro_rdm_pg`; API 3370; túnel temporal (origen no publicado), **cerrado** al terminar.
- **Datos:** exclusivamente sintéticos (cuenta `agricultor15`, «Rosa Vargas (sintética)»). No se tocó la DEMO (`.demo`), ni `.et1`/`.et1o`, ni el `Pixel_8` compartido.

## Pruebas

| Qué | Comando | Resultado |
|---|---|---|
| Análisis | `flutter analyze` | sin avisos |
| Suite completa sobre `e6d72b3` | `flutter test --concurrency=4` | 3042 pasan, 3 omitidas, 0 fallan (05:35) |
| Suite completa sobre `6b397c9` | `flutter test --concurrency=4` | **3044 pasan, 3 omitidas, 0 fallan** (06:34) |
| Pruebas focalizadas tras cada fusión | ver `COORDINACION.md` | verdes |

## APK

- `rdm_env.sh build-app` sobre `6b397c9` (árbol limpio): APK profile x86_64 `com.comunidad.agro.agroquimicos.rdm` («AC RDM»), SHA-256 `8dec42ebc6bc63c51fad8a967bd803b1c8f16aedcd72081bd267573e0822dfb0`, 376 MB (con los modelos de voz verificados el 2026-11-12).
- **Instalada en `emulator-5556`** como actualización de `c1e2639` (instalada primero, SHA-256 `5940c96a…5584`): `Success`; la activación, el titular y los datos se conservaron (`e09` en adelante tras actualizar).
- **Atada al túnel del 2026-11-12, ya cerrado:** funciona sin conexión; para sincronizar hay que abrir otro túnel y recompilar desde el mismo SHA.
- El `Pixel_8` compartido (`emulator-5554`) conserva una `.rdm` **antigua** (`2d6aa0d`, bloque 1); ese emulador terminó solo (código 139) tras el uso de la sesión F y no se volvió a arrancar. Ver «Pendiente».

## Recorrido real en el emulador (`e01`–`e24`)

1. Arranque sin activar (`e01`) → «Activar en línea» (`e02`): correo sintético tecleado; la contraseña de un solo uso la tecleó `demo-rica.cjs credential-adb` en el campo enfocado; la captura `e03` se tomó con el campo ya enmascarado (sin carácter visible).
2. Titular (`e04`–`e06`): «Crear el titular», «Rosa Vargas», compartido. **Hallazgo corregido** en `1a04963`: el texto decía «Operaciones › Más › Modo de uso» (camino de la barra antigua). PIN (`e07`): «Ahora no»; el mismo texto viejo, corregido.
3. Inicio vacío (`e08`) con la cabecera de B, «Sin campaña activa» y el engranaje.
4. Actualización a `6b397c9` sin perder datos. Campaña «Invierno 2026» creada desde el selector de campaña de Inicio (`e09`, diálogo con el estilo nuevo; `e10`, tarjeta oscura «Campaña actual»).
5. **Compra manual SIN CONEXIÓN** (`svc wifi disable` + `svc data disable`; `ping` sin respuesta): proveedor y producto creados desde los selectores (`e12`–`e15`); con el teclado abierto un toque fuera del precio cerró la hoja, Atrás ofreció «¿Descartar cambios?» y «Seguir editando» devolvió el borrador con la cantidad (`e16`–`e17`); 5 L × 80 Bs = **400,00 Bs** (`e18`); «Una persona» → Rosa Vargas; paso 2 sin respuesta de pago por defecto (`e19`); «Todavía no» y «Confirmar compra» (`e20`).
6. **Persistencia:** `am force-stop` y relanzar → Actividad muestra la compra, 400,00 Bs, «Sin pagar» (`e21`).
7. **Efectos en la base local** (copia de sólo lectura con `run-as`; esquema **18**): 1 compra `CONFIRMED`, `total_bob_minor` 40000; 1 línea 5000 unidades base × 8000 centavos; 1 asignación a la persona 1 (`BY_ACTUAL_USAGE`); **0** pagos al proveedor; 1 lote de 5 L; 1 movimiento de inventario; `sync_outbox` vacío (las compras no se envían al sindicato).
8. Red restaurada; Sindicato, Almacén, Personas y Actividad en el dispositivo (`e22`–`e24`, `e21`).

## No verificado aquí (declarado)

- **Voz:** el AVD propio arrancó sin audio; la integración de estados de voz se verificó en el bloque 1 (`d02`–`d08`) y por pruebas; la precisión del reconocimiento con voz humana sigue pendiente de un teléfono físico. No se guardó audio ni transcripción.
- Letra ampliada y 360 dp: en el arnés (`tool/rediseno/capturas_*_test.dart`), no cambiando la escala del emulador.
- Sincronización real con la Central tras la compra sin conexión (las compras no van a la cola; consumo y convocatorias no se recorrieron con red en esta sesión).
- Recorridos en el emulador de las pantallas de A, B y C más allá de su apertura (aplicación, plan, pago, transferencia, convocatorias): probados automáticamente y revisados en capturas del arnés, **no** recorridos aquí.
- Nada de esto está **revisado por el usuario**.
