# F04-AV — Comprobación Android sin red de los avisos (EMULADOR)

| Campo | Valor |
|---|---|
| Fecha real | 2026-11-01, de 09:00Z a 09:48Z (madrugada del 2026-11-01 en Bolivia) |
| Código | Mobile `f99fc56`, rama `feat/f04-av-avisos-inventario` |
| APK | `agrocuentas.av1-profile-x64.apk`, profile x86_64, 49 823 310 bytes, SHA-256 `9a1ecf6413f3da345aeab2d9d9517a9ff00fd411a4ffd3d31d89f1e7adae953c`, compilada 09:20:15Z–09:21:58Z desde ese HEAD exacto, sin cambios versionados |
| Paquete | `com.comunidad.agro.agroquimicos.av1`, etiqueta «AC AVISOS»; instalación nueva (no existía) |
| Dispositivo | **EMULADOR** `Pixel_8`, Android 16 / API 36, modelo `sdk_gphone16k_x86_64`, zona `America/La_Paz` |
| Central | Propio y desechable: contenedor `agro_a_av_pg` (127.0.0.1:55497, base `agro_av`, 13 migraciones), API 3200 con `dist` de Backend `9233acc`, observador 3201, túnel temporal sólo hacia esa API |
| Datos | Sintéticos: tenant `av-sindicato`, cuenta `u1-av`, «Titular AV», «Hermana Demo», «Vecino Demo» |
| Issues | Refs #168, #169, #170, #171 |
| Origen | Comprobación nueva. No es DEVICE |

## 1. Preparación

1. Docker Desktop arrancado; `av.sh up`: PostgreSQL propio, migraciones, API (health 200) y siembra del tenant sintético.
2. `av.sh tunnel`: origen HTTPS temporal (health 200; el valor no se publica).
3. APK compilada desde `f99fc56`. Una APK anterior, de `e6cc25e`, se descartó sin instalarse al aplicar la revisión.
4. Emulador arrancado (09:22:10Z, listo 09:22:48Z); instalación sólo de `.av1`.
5. Activación por la interfaz en modo **compartido**, con contraseña de un solo uso (no se muestra ni se guarda) y PIN sintético que vive sólo en la memoria de un proceso guardián.
6. Siembra sintética relativa al día sobre una copia de la base: SHA-256 antes `173b5208…`, después `0781cd48…`, igual en el PC y en el emulador. El cálculo en HOST de esa misma base dio:

```text
expired:  Glifosato Demo|GLI-VENCIDO|Titular AV|3000|1 ; Glifosato Demo|GLI-VENCIDO|Vecino Demo|1000|1 ; Paraquat Demo|PQ-ARCH|Titular AV|1000|1
dueToday: Atrazina Demo|ATR-HOY|Titular AV|1000|0
near:     Glifosato Demo|GLI-PRONTO|Titular AV|3000|10
unknown:  Mancozeb Demo|Titular AV|5000
low:      Glifosato Demo|Hermana Demo|2000|9000 ; Glifosato Demo|Vecino Demo|1000|9000 ; Mancozeb Demo|Hermana Demo|0|5000
withoutLevel: Atrazina Demo
```

## 2. Sin red

Modo avión activado a las 09:25:33Z: `airplane_mode_on=1`, Wi‑Fi desactivado, «Active default network: none». La zona se volvió a fijar después de cada cambio de modo avión.

Hubo dos tramos sin red. Entre ellos se restableció el PIN con red (§5).

| Tramo | Inicio – fin (UTC) | Peticiones del observador al empezar | Al terminar |
|---|---|---|---|
| 1 | 09:25:33 – 09:33:23 | 5 (las de la activación) | 5 |
| Con red, restablecer el PIN | 09:33:48 – 09:35:56 | 5 | 7 (`POST /auth/v2/login`, `POST /auth/v2/logout`) |
| 2 | 09:35:57 – 09:46:13 | 7 | 7 |

## 3. Resultados

| ID | Resultado | Lo observado |
|---|---|---|
| AV-A1 | PASS | «Avisos de inventario» se abre y calcula en modo avión; resumen del inventario: «3 vencidos · 1 vence hoy · 1 por vencer · 3 bajos por responsable · 1 sin fecha registrada» |
| AV-A2 | PASS | «Vencidos (3)»: Glifosato GLI-VENCIDO del titular, 3 L, y del vecino, 1 L, «hace 1 día»; Paraquat PQ-ARCH |
| AV-A3 | PASS | «Próximos a vencer (1)»: GLI-PRONTO «en 10 días», «Aviso: 30 días antes (valor inicial)» |
| AV-A4 | PASS | GLI-LEJOS de Hermana, a 90 días, no aparece en ninguna sección |
| AV-A5 | PASS | «Sin fecha de vencimiento registrada (1)»: Mancozeb del titular, 5 KG |
| AV-A6 | PASS | No hay sección de total bajo. «Existencia baja por responsable (3)»: Glifosato Hermana 2 L y Vecino 1 L, «En toda la instalación: 9 L»; Mancozeb «Hermana Demo no tiene existencias propias; nivel mínimo 2 KG. En toda la instalación: 5 KG» |
| AV-A7 | PASS | «Atrazina Demo no tiene nivel mínimo: no se avisa cuando queda poco…» |
| AV-A8 | PASS | Tocar «Glifosato · Hermana» abre el detalle del producto, sin iniciar operaciones. Al volver, tras cambiar la configuración (AV-A17), la vista recalculó: «Aviso: 20 días antes» y «Existencia baja por responsable (2)» |
| AV-A9 | PASS | Corregir el número de GLI-PRONTO pidió datos, motivo y PIN. Detalle e historial: «…lote GLI-PRONTO → GLI-PRONTO-XXX… Motivo: Leido en el envase ensayo AV. Autorizó Titular AV con PIN; 1 lote cambiado.» Base: corrección 1, `LOCAL_PIN`, 1 fila de lote |
| AV-A10 | PASS | Corregir GLI-VENCIDO a GLI-VENCIDO-B cambió el lote 1 (titular) y el lote 6 (vecino, hijo por transferencia). Base: corrección 2, 2 filas de lote, `unproven_lot_count = 0`. La vista muestra GLI-VENCIDO-B del vecino |
| AV-A11 | PASS | La compra revertida (Atrazina, ATR-REV) se consulta con su número de lote y no ofrece «Corregir vencimiento o lote». No muestra «Ver correcciones» porque no tiene ninguna; el historial de una compra revertida está cubierto en HOST |
| AV-A12 | PASS | Aplicación sin red de 1 L de Glifosato del titular, guardada sin bloqueo. `application_consumptions`: 1000 del lote 1 (GLI-VENCIDO-B, el más antiguo, vencido) |
| AV-A13 | PASS | 0 peticiones nuevas en los dos tramos sin red (§2) |
| AV-A14 | PASS | «Vence hoy (1)»: Atrazina ATR-HOY del titular, 1 L, en tarjeta ámbar con icono de advertencia, entre «Vencidos» y «Próximos» |
| AV-A15 | PASS | Reloj del emulador a 23:59:01 del 01/11 (hora automática desactivada): ATR-HOY sigue en «Vence hoy». A las 00:00:07 del 02/11, «Volver a calcular»: ATR-HOY en «Vencidos (4)», «Venció el 01/11/2026, hace 1 día»; GLI-PRONTO «en 9 días». Reloj y hora automática restaurados |
| AV-A16 | PASS | Paraquat, archivado con nivel 2 L y 1 L: PQ-ARCH en «Vencidos»; Paraquat no aparece en existencia baja ni como «sin nivel mínimo» |
| AV-A17 | PASS | Sobre Glifosato. «Guardar» inactivo sin cambios (`enabled="false"`); 366 días → «Escriba un número entero de días, de 0 a 365.». Mínimo 1 y plazo 20 → un solo diálogo de PIN con «Nivel mínimo: 3 L → 1 L. Aviso de vencimiento: 30 días (valor inicial) → 20 días». Cancelar en el PIN: base sin cambios (3000, NULL). Guardar con el PIN: base 1000 y 20 |
| AV-A18 | PASS | 101 caracteres: «El número de lote admite hasta 100 caracteres; tiene 101. Revise lo escrito: no se recorta.», contador «101/100», el campo conserva los 101 caracteres y «Continuar» queda inactivo. Con 100 caracteres se guardó exacto: `length(new_lot_number) = 100` y el lote igual |

**Lo guardado.**
- **Integridad.** La base final pasa `PRAGMA integrity_check = ok`, con `user_version = 12`.
- **Movimientos y lotes.** Entre la copia previa a AV-A8 y la posterior a AV-A10, los movimientos de inventario son idénticos, y los lotes sólo cambian en vencimiento y número.
- **Correcciones.** Hay exactamente dos.

Copias de la base, SHA-256 abreviado, en `%TEMP%\agro_a_av_env\device\`:

| Copia | SHA-256 |
|---|---|
| `seed` | `0781cd48…` |
| `a17_guardado` | `25adbd27…` |
| `a9` | `ef381042…` |
| `a10` | `5726ff52…` |
| `antes_a12` | `b107d2b3…` |
| `fin` | `162d0626…` |

## 4. Desvíos del protocolo

- **AV-A17 se hizo sobre Glifosato, no sobre Mancozeb.** Así sirvió también para el recálculo de AV-A8.
- **AV-A12 necesitó un chaco del titular, que la siembra no creaba.** Se creó por la interfaz, sin red: «Chaco Titular AV», 1 ha, sintético.
- **AV-A9 se hizo con el valor de 100 caracteres de AV-A18.** Fue una sola corrección.

## 5. Incidente: un PIN sintético quedó expuesto en la salida de la sesión

**Qué pasó.**
- En el primer intento de AV-A9, el texto del motivo contenía paréntesis y el teclado por ADB lo rechazó, así que el motivo quedó vacío.
- El paso siguiente pidió al guardián que tecleara el PIN, que cayó en el campo del motivo, un campo de texto visible.
- Un volcado de pantalla posterior lo mostró en la salida de herramientas de la sesión.
- No se guardó en ningún archivo, captura ni registro del entorno: una búsqueda en `%TEMP%\agro_a_av_env` no lo encontró. Tampoco se guardó en la base: el diálogo se canceló y la base tenía 0 correcciones.

**Qué se hizo.**
1. Se vació el campo sin volver a mostrar la pantalla y se canceló el diálogo.
2. El guardián terminó y descartó ese PIN.
3. Se abrió un tramo con red sólo hacia el Central propio. Se acreditó la cuenta con otra contraseña de un solo uso y se **restableció el PIN** con uno nuevo, generado y tecleado por otro guardián, que nunca se mostró. Restablecer invalida las autorizaciones del PIN anterior.
4. Se añadió una guarda (`_wt/tools/av/pin_safe.sh`, sin commitear): el guardián sólo teclea si el `EditText` enfocado tiene `password="true"`. En su primer uso se detuvo sin teclear, porque leía el nodo de la ventana; se corrigió para leer el `EditText` enfocado.
5. Las comprobaciones con PIN (AV-A9, A10, A17) se repitieron o hicieron después del restablecimiento.

El valor expuesto era un PIN sintético de una instalación aislada con datos sintéticos, y ya no es válido. No se repite aquí.

**Otra captura retirada.** Una captura del diálogo de PIN de AV-A17 (`av08`), con el campo vacío, se borró por la regla del protocolo de no capturar pantallas de PIN.

## 6. Observaciones

- **El botón flotante «Nuevo» de Inventario tapa parte del último aviso visible.** Se ve en la capa inferior de la vista. El aviso sigue siendo legible al desplazarse.
- **Un producto archivado sigue apareciendo en el selector de productos de la aplicación, con su disponible.** Es comportamiento existente, fuera de este bloque. Sus existencias pueden usarse.
- **La compra revertida por la siembra muestra «Actor no registrado».** La siembra usó la reversión de pruebas sin autorización; es un dato sintético.

## 7. Capturas

En `%TEMP%\agro_a_av_env\capturas\`, sin barra de estado. No se commitean. Ninguna muestra un PIN ni una contraseña.

| Captura | SHA-256 |
|---|---|
| `av01_inventario_resumen` | `33aa7b74…` |
| `av02_avisos_arriba` | `10324fd2…` |
| `av03_avisos_medio` | `51d2af05…` |
| `av04_avisos_abajo` | `cf06690e…` |
| `av05_producto_desde_aviso` | `719dea79…` |
| `av06_config_sin_cambios` | `fe5c4d6b…` |
| `av07_config_366` | `51410b74…` |
| `av09_config_guardada` | `f8d6383b…` |
| `av10_avisos_recalculados` | `53a5d5fb…` |
| `av11_detalle_gli_pronto_antes` | `f61bf14a…` |
| `av12_lote_101` | `9a580b50…` |
| `av13_motivo_efectos` | `196dbebe…` |
| `av14_detalle_gli_pronto_corregido` | `8917f487…` |
| `av15_historial_gli_pronto` | `514e9ff0…` |
| `av16_detalle_gli_vencido_corregido` | `aff1fe71…` |
| `av17_compra_revertida` | `e3436e7f…` |
| `av18_2359_vence_hoy` | `f0f96c48…` |
| `av19_0000_vencido` | `3108ab20…` |

## 8. Cierre

| Paso | Hora (UTC) | Resultado |
|---|---|---|
| Reloj del emulador vuelto a la hora real | 09:47:51 | `auto_time = 1`; modo avión desactivado; zona `America/La_Paz` |
| Guardián del PIN terminado | | PIN descartado |
| `av.sh down` | | Túnel, observador y API detenidos. Contenedor `agro_a_av_pg` detenido, con los datos conservados en `agro_a_av_pgdata` |
| Emulador | | Apagado con `emu kill` |
| Docker Desktop | | Detenido; se había arrancado para esta sesión |

**Sin cambios:** `font_scale = 1.0` y `wm size` 1080x2400.

**Datos que se conservan:** el paquete `.av1` instalado, `%TEMP%\agro_a_av_env` y el volumen.

**Lo que no se tocó:** EXP (`.expa`–`.expe`), UX (`.uxc1`, `.uxc2`), `.ens1`, `.f10eval`, la app normal, ni sus contenedores.

## 9. Límites

- Es un EMULADOR x86_64, no un teléfono. **DEVICE sigue NOT_RUN**: no había ningún teléfono conectado.
- Un solo recorrido, por ADB, sin participante. No es una evaluación con usuarios.
- **El volcado de `uiautomator` filtra las líneas con muchas mayúsculas seguidas**, por eso los números de lote largos no se ven en él. Para AV-A18 se leyó el atributo `text` del nodo y se comprobó en la base.
