# Bloque 2: comprobaciones en EMULADOR (2026-10-28)

**Fecha real:** 2026-10-28, de las 11:46 a las 18:03 (America/La_Paz). Sesión A.
- 11:46: apertura del túnel. El observador ya había registrado un `GET /health` a las 11:44.
- 18:03: cierre del entorno (22:03Z).

**Procedencia:** EMULADOR.
- AVD `Pixel_8`: Android 16 / API 36, x86_64, 1080 × 2400, 420 dpi, zona horaria America/La_Paz.
- Había un teléfono físico conectado y **no se usó**.
- **No es una sesión de usabilidad ni una evaluación humana.** Un solo operador recorrió el arnés con datos sintéticos. No se miden tiempos humanos.

**Decisiones que se comprueban:** son del autor (Roderich Rendón) del 2026-10-27 (D-03, D-04, E-15, D-07, E-12) y del 2026-10-28 (D-03: anulaciones demostradas). El alcance a las operaciones tardías RF-03, confirmado por el autor el 2026-10-28, no se recorrió en el emulador (ver Límites). No se atribuye aprobación al tutor ni a la Directiva.

**Central desechable:**
- PostgreSQL 16 nuevo con 13 migraciones; API `dist` del Backend `4bcb1ea`. Frente a `main` `383be48` sólo difieren una prueba con su soporte y la validación de fecha del script de siembra; el resto de `Back/src` y las migraciones no cambian.
- Configuración: `NODE_ENV=development`, divulgación `provisional-synthetic`, sellado desactivado, `SYNC_V1_PRODUCTION_ADMISSION=enabled`.
- Siembra DS-UX `movil` INT5 con S = 2026-10-27: inquilino `f10ux-movil-int5`, cuentas T01 y T02.
- Túnel HTTPS temporal autorizado por Roderich y observador que enmascara los UUID. La URL no se publica.

**Siembra Mobile:** DS-UX-1 en COMPARTIDA con S = 2026-10-28. El oráculo inicial dio «consistent» (Glifosato Demo 5 L, Bellator 1 L del titular).

**Secretos:**
- Las contraseñas son de un solo uso y se asignan y teclean en un mismo proceso, sin mostrarse.
- El PIN sintético vivió sólo en la memoria de un proceso, que lo tecleaba cuando recibía una señal y lo descartó al terminar.
- No se capturó ninguna pantalla mientras se escribía un secreto.

**Al terminar:** la API, el túnel y el observador se detuvieron, el contenedor se conservó y el paquete de prueba se desinstaló.

## APK usadas

| Id | Código (composición local, publicada en #161) | SHA-256 (= `base.apk` instalado) | Paquete |
|---|---|---|---|
| **APK-1** | `e5ba07c` (D-03 **antes** de las anulaciones demostradas) | `f87932cd6a90c8523f36a40f73cd79790232e35cf872ec8d42006d9ad55641e2` | `com.comunidad.agro.agroquimicos.f10int5`, profile x86_64 |
| **APK-2** | `fb331c6` (D-03 **corregido**: anulaciones demostradas) | `5a296dbebb0ffef6ef1803aabb023c5bf841b4428ae172f0871839669fdfffc4` | ídem |

Entre `e5ba07c` y `fb331c6` sólo cambia D-03: su parte de `lib/data/agro_repository.dart`, sus pruebas y su documentación. Los demás frentes son idénticos en las dos APK.

## Recorridos

| # | APK | Frente | Recorrido | Resultado |
|---|---|---|---|---|
| E1 | APK-1 | E-12 | T02 en instalación limpia: activación → «Titular de los datos» → «Confirmar titular» → oferta → PIN dos veces → «Crear PIN» | PASS. Oferta: «Le recomendamos crear ahora el PIN del titular…» y «Acaba de confirmar su cuenta en línea, así que ahora no hace falta volver a escribir la contraseña…», sin campo de contraseña. Resultado: «PIN del titular creado. Funciona sin conexión.». El Central no recibió ninguna petición durante la creación del PIN |
| E1 | APK-1 | E-12, RF-13 | En modo avión, revertir la compra DSUX-INI-2 con el motivo «Prueba E1 sin red» y el PIN | PASS. «Revertida Autorizada». `reversal_audit` registra `LOCAL_PIN` y el motivo |
| D-07 | APK-1 | D-07 | Titular → Familiar Demo, 1 L de Glifosato Demo | PASS. Antes de confirmar: «Esta transferencia entrega producto a Familiar Demo, pero no genera una deuda.» y «Esta transferencia no registra ningún cargo ni cobro a Familiar Demo…». La lista dice «Entrega sin deuda». `account_transactions` pasa de 0 a 0 |
| D-03 (anterior) | APK-1 | D-03 | Aplicación del titular con fecha 15/10, 1 L; la compra es del 18/10 | PASS. «Glifosato Demo: el 15/10/2026 esa persona no tenía este producto; pidió 1 L. …». `applications` pasa de 0 a 0 |
| E-15 | APK-1 | E-15 | Aplicación del titular de hoy, 1 L | PASS. «Costo propio: 45,00 Bs (queda anotado en la cuenta de Titular)». Se conserva el `USAGE_CHARGE` de 4500 |
| D-04/E-15 | APK-1 | D-04, E-15 | Familiar Demo aplica 0,5 L en su chaco → Cuentas | PASS. «Consumo y costos propios · Titular · Consumo aplicado (costo FIFO) · Verano Demo 45,00 Bs … (no son deuda)». Familiar Demo: «Deuda pendiente por origen · Verano Demo 22,50 Bs». La lista sólo tiene esas dos tarjetas: el titular no aparece como deudor (captura `d04_02_cuentas.png`). Personas y «Movimientos propios» no se recorrieron |
| D-04 | APK-1 | D-04 | Filtro «Todas las campañas» → «Registrar pago» de 10 Bs a Familiar Demo | PASS. El diálogo dice «Se registra sin campaña» y «Se aplica primero a la deuda más antigua, de cualquier campaña.». Mensaje: «Pago de 10,00 Bs registrado a Familiar Demo. Imputado: Verano Demo 10,00 Bs.». En la base, `PAYMENT` −1000 con `campaign_id` nulo y `payment_allocations` (pago 3 → cargo 2, 1000). Deuda pendiente 12,50 |
| D-04/E-15 | APK-1 | C-09 | Inicio | PASS. «Familias por cobrar 12,50 Bs», sin el titular, y «Pagos recibidos 10,00 Bs» |
| E2 | APK-1 | E-12 | T01 en instalación limpia (`pm clear` sólo del paquete de prueba): activación → titular → «Ahora no» | PASS: entra al Inicio sin PIN. El aviso «Puede crear el PIN más tarde…» no se capturó, porque desapareció antes del volcado |
| E2/E3 | APK-1 | E-12 | Revertir una compra sin PIN → «Configure el PIN del titular primero.» → «Configurar PIN» → «Primero confirme la cuenta del titular en línea.» (correo y contraseña) → «Confirmar en línea» → PIN dos veces → «Guardar PIN» → «Volver» | PASS. Se exige la contraseña (E2). Al volver aparece «¿Revertir esta compra? PIN del titular configurado. Revise la operación y autorícela con su PIN.», con el motivo «Prueba E3 retorno» conservado. La compra seguía `CONFIRMED`: no se ejecutó sola. Con el PIN y «Autorizar» queda «Revertida Autorizada» |
| D-03 (corregido) | **APK-2** | D-03 (2026-10-28) | Misma instalación de E2: aplicación de 5 L el 20/10 → revertida hoy con el motivo «Registrada por error» y el PIN → aplicación de 5 L el 19/10 | PASS. La bitácora conserva `APPLICATION_OUT` del 20/10 y `APPLICATION_REVERSAL` del 28/10. La aplicación del 19/10 **se acepta**, con 225,00 Bs y el mismo FIFO. Con la proyección de APK-1, ese cupo habría sido 0: es un cálculo, no se ejecutó con APK-1 |
| D-03 (corregido) | **APK-2** | D-03 | Otra aplicación el 19/10 | PASS. El formulario dice «Esta persona no tiene productos en existencia»; el saldo de hoy del lote es 0. En el emulador sólo se vio ese bloqueo del formulario. Que la proyección no duplique disponibilidad y el rechazo con «quedan …» están probados en host (3c-bis y el pase de dos lotes) |

## Peticiones por el túnel (observador, UUID enmascarados)

| Veces | Petición | Estado |
|---|---|---|
| 3 | `POST /api/v1/auth/v2/login` | 200 |
| 3 | `GET /api/v1/health` | 200 |
| 2 | `POST /api/v1/auth/v2/session/client` | 201 |
| 2 | `POST /api/v1/auth/clients` | 201 |
| 2 | `GET /api/v1/auth/v2/me` | 200 |
| 1 | `POST /api/v1/auth/v2/logout` | 204 |

Corresponden a las dos activaciones (E1 con T02 y E2 con T01) y a la confirmación de cuenta de E3, que cierra su sesión.

## Límites

- **No ejecutado en el emulador:**
  - el retorno desde una operación tardía: la siembra no tiene ninguna campaña cerrada; queda cubierto en host (W4, W3b);
  - la confirmación de una operación tardía (RF-03) con la proyección corregida de D-03, por la misma razón; está cubierta en host;
  - las familias de rechazo de sincronización;
  - la exportación CSV/PDF;
  - F08.
- **E4**, la mediana del tiempo entre activar y crear el PIN, no se mide sin personas. El tiempo técnico de E1, unos 3 min 13 s con reintentos del arnés, no es un dato de usabilidad.
- **Sin evaluación humana nueva.** No cambia ningún instrumento, umbral ni dato de X01/X02.
- **Archivos conservados fuera del repositorio:** 15 capturas, las bases finales y el registro del observador.
