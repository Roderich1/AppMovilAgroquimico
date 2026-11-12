# Rediseño móvil · integración de las sesiones A, B, C y F — evidencia

- **Fecha real:** 2026-11-12 (UTC−4), tarde y noche.
- **Rama / worktree:** `feat/rediseno-movil` en `_wt/RDM-MOB` (rama de integración). Sin push.
- **Commits verificados:** `6b397c9` (suite completa; APK de `e01`–`e24` y `f01`–`f13`) y **`d6c4c4d`** (corrige el defecto de Actividad hallado en el recorrido; pruebas focalizadas; APK de `f14`–`f17`, **la instalada para la revisión**). Entre `6b397c9` y `06d805e` sólo cambió documentación. Coordinación y entregas integradas: `docs/rediseno/COORDINACION.md`.
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

## Segundo recorrido (`f01`–`f17`, tarde del 2026-11-12)

Lecturas de la base antes y después de cada operación (copia de sólo lectura con `run-as`, esquema 18). Datos sintéticos: se añadieron Juan Mamani (familiar) y los chacos «Chaco Rio» (Juan, 2 ha) y «Chaco Norte» (Rosa, 3 ha) desde Ajustes › Datos.

| Recorrido | APK | Antes → después en la base |
|---|---|---|
| **Transferencia** Rosa → Juan, 2 L (`f01`, `f02`) | `6b397c9` | transfers 0→1 (2000 u., 16000 cent., `CONFIRMED`); lote hijo de 2 L para Juan con el mismo costo (8000/L); movimientos `TRANSFER_OUT −2000` y `TRANSFER_IN +2000`; **account_transactions 0→0** (el formulario avisa que no genera deuda) |
| **Plan** Chaco Rio, 0,5 L/ha × 2 ha (`f03`) | `6b397c9` | application_plans 0→1 `PLANNED`, ítem 1000 u. — **defecto**: Actividad seguía en «No hay planes pendientes» hasta cambiar de pestaña |
| **Aplicación desde el plan** (`f04`) | `6b397c9` | plan → `APPLIED`; aplicación `CONFIRMED` 8000 cent.; consumo de 1 L del lote de Juan; `APPLICATION_OUT −1000`; cargo `USAGE_CHARGE +8000` a Juan («Se cargará a Juan Mamani: 80,00 Bs») |
| **Pago** de Juan, 50 Bs de 80 (`f05`–`f07`) | `6b397c9` | `PAYMENT −5000`; payment_allocations 1 (5000 al cargo); provider_payments sin cambios (0); aviso «Imputado: Invierno 2026 50,00 Bs»; saldo 30,00 Bs |
| **Excel** «Resumen de campaña» (`f08`, `f09`) | `6b397c9` | archivo `.xlsx` en la carpeta de la app; leído fuera: 1 compra 400,00; 1 aplicación 80,00; 0 planes pendientes; deuda 30,00 (coincide con la base) |
| **PDF** «Estado de cuenta» de Juan (`f10`) | `6b397c9` | cargo 80,00, crédito 50,00, saldo 30,00 (coincide). Columnas truncadas con «…» en A4 vertical: maquetación del reporte, anterior al rediseño |
| **Borrador** de aplicación (`f11`–`f13`) | `6b397c9` | Atrás → «¿Descartar cambios?»; «Seguir editando» conserva; app al fondo y vuelta conserva; paso 2 → paso 1 → paso 2 conserva la mezcla; abrir y cerrar el panel de voz sin hablar no cambia nada; «Descartar cambios» sale y el formulario se reabre vacío; **la base no cambia** |
| **Corrección** (`f14`) | `d6c4c4d` | plan para Chaco Norte guardado desde «+ Registrar» aparece en Actividad en el acto |
| Almacén (`f15`) | `d6c4c4d` | 4 L, «Previsto en planes 1,5 L · quedarán 2,5 L», valor 320,00 Bs |
| Convocatorias sin servidor (`f16`, `f17`) | `d6c4c4d` | lista vacía con su explicación; «Actualizar» sin servidor → «El resultado remoto no puede confirmarse. No se reutilizará la credencial anterior…» e Inicio ofrece «Volver a autenticar». Comportamiento previsto ante un resultado indeterminado; los datos locales no cambian. Al reconectar habrá que volver a autenticar |

**APK instalada para la revisión:** `d6c4c4d`, SHA-256 `392f2f1e19ae2c39d9fa7d1eda1ff9a64d40e2d923e44c07a1aab9f366c791d7`, actualización sobre `6b397c9` (`Success`; todos los conteos iguales antes y después). Compilada **sin túnel** (origen `https://sin-tunel.invalid`): no llega a ningún servidor.

### Bloqueo de entorno

Abrir el túnel HTTPS temporal (`rdm_env.sh tunnel`) fue **denegado** por los permisos de esta sesión (exposición externa). La app sólo acepta un origen HTTPS compilado, así que sin túnel no se pudo recorrer en el teléfono: participación en convocatorias y sus estados de envío con servidor, publicación de consumo y necesidad, vínculos, reautenticación. Esas funciones tienen cobertura automática y capturas del arnés; el recorrido queda pendiente de que el autor abra el túnel o autorice abrirlo.

**Sincronización, separada:** (1) persistencia local: verificada arriba; (2) publicación autorizada: `sync_outbox` siguió vacío durante todo el recorrido, porque compras, transferencias, aplicaciones y pagos privados no se envían al sindicato y no se publicó consumo; (3) recepción del servidor: no verificable sin túnel.

## No verificado aquí (declarado)

- **Voz:** el AVD propio arrancó sin audio; la integración de estados de voz se verificó en el bloque 1 (`d02`–`d08`) y por pruebas; la precisión del reconocimiento con voz humana sigue pendiente de un teléfono físico. No se guardó audio ni transcripción.
- Letra ampliada y 360 dp: en el arnés (`tool/rediseno/capturas_*_test.dart`), no cambiando la escala del emulador.
- Sincronización real con la Central tras la compra sin conexión (las compras no van a la cola; consumo y convocatorias no se recorrieron con red en esta sesión).
- Convocatorias con servidor (participación, estados de envío), vínculos, necesidad y consumo publicados: **bloqueados** sin túnel (ver «Bloqueo de entorno»). Aplicación, plan, pago, transferencia, reportes y borrador: recorridos en el segundo recorrido.
- Comparativas lámina | integración: `comparativas/` (49), con capturas del arnés sobre la rama integrada (`tool/rediseno/capturas_{arnes,a,b,c}_test.dart` en `6b397c9`) o del emulador cuando lo indica el rótulo.
- Nada de esto está **revisado por el usuario**.
