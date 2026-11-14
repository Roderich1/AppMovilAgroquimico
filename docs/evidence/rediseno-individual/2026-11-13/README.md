# Modo individual — evidencia (2026-11-13)

Verificado el 2026-11-13 sobre `feat/modo-individual`. Datos exclusivamente sintéticos. Nada de esto es la aceptación visual del autor.

## Pruebas automáticas

| Qué | Commit | Comando | Resultado |
|---|---|---|---|
| Análisis | `b8248fb` | `flutter analyze` | Sin avisos |
| Suite completa | `1f46a9c` | `flutter test --timeout 180s` | 3164 pasan, 3 omitidas, 2 fallos |
| Los 2 fallos, tras corregir | `580fbb0` | `flutter test test/reports_screen_test.dart test/purchases_access_test.dart test/ind_orq_test.dart` | 37/37 |
| Focalizadas tras el recorrido | `b8248fb` | `ind_orq`, `ind_a_*`, `ind_b_*`, `personal_mode_flows`, `purchases_access`, `rdm2_a_hoja_compra`, `formulario_unico_accesos` | 54/54 y 21/21 |

Los 2 fallos de la suite eran **defectos nuevos de la integración**, no anteriores ni intermitentes:
- `purchases_access_test` (guardia de rutas): `/chacos/costos` sólo se citaba dentro de un ternario. Corregido citándola de forma literal.
- `reports_screen_test` («se llega desde Operaciones…»): fallaba siempre con `!timersPending`. Pasaba en las ramas A, B y C por separado. La causa era una segunda lectura de Inicio al cargar la modalidad (`null` → compartido). Ahora Inicio sólo relee al entrar o salir del modo individual.

No se repitió la suite completa sobre `b8248fb`. Los cambios posteriores a `580fbb0` son de texto y de navegación, y se cubrieron con las pruebas focalizadas de arriba.

## Recorrido en emulador (no es un teléfono físico)

- **Dispositivo:** AVD `RDM_Pixel8` (`emulator-5556`), `sdk_gphone16k_x86_64`, Android 16, 1080×2400.
- **APK:** `com.comunidad.agro.agroquimicos.ind` («AC IND»), profile x64, compilada desde `b8248fb`, SHA-256 `3ee883f783325ccb739a1b947ff90f895d3cfbfd9e50b09472bc42a76c3f5cdb`. La primera candidata fue `580fbb0` (`d1035b8b…`).
- **Central:** aislada y propia (`agro_ind_pg` 15438, API 3390, Backend congelado `_wt/RDM-BE` `49ed870`), sembrada con `ind_env.sh seed` y la cuenta sintética `agricultor15`. La alcanzaba un túnel HTTPS temporal autorizado por el autor, **cerrado** al terminar. Después se detuvo la Central y se conservó el volumen.
- **Instalación de revisión del modo con varias personas:** `.rdm` sigue instalada y no se tocó.

| Paso | Capturas | Efecto comprobado |
|---|---|---|
| Activación y alta del titular «Rosa Vargas» eligiendo «Modo individual» | `e00`–`e04` | Aviso «Usa el modo individual». No se forzó la bandera ni se borraron datos. |
| Inicio sin campaña, campaña nueva, Inicio vacío (I-02) | `e05`–`e07` | Sin cifras en cero. |
| Chacos vacío (I-43) y alta de «Chaco Norte», 3 ha | `e08`–`e09` | El propietario es el titular sin elegirlo. El arnés escribió mal la superficie y la app lo rechazó con su validación. |
| Compra a crédito de 2 productos (12 L × 118 y 4 KG × 150), con teclado | `e10`–`e13` | Total 2.016,00 Bs. Sin «¿Para quién es?». |
| Confirmación con doble toque | `e14` | **Una** compra; Inicio muestra «1 compra pendiente de pago». |
| Actividad (I-04), Registrar (I-03) y Proveedores (I-05) | `e15`–`e17` | Deuda real 2.016,00 Bs. |
| Pago parcial de 1.000 Bs al proveedor | `e18`–`e19` | Deuda 1.016,00 Bs. |
| Aplicación de 2 L en 1 ha de 3 (I-20 a I-22) | `e20`–`e25` | Herbicida pasa de 12 a 10 L; valor de 1.416 a 1.180 Bs; costo 236,00 Bs. |
| Plan de 3 KG de fertilizante (I-23, I-24) | `e26`–`e28` | Existencias sin cambio (4 KG); «Previsto en planes 3 KG · quedarían 1 KG». |
| Inicio (I-01), Chacos, detalle y costos (I-40 a I-42) | `e29`–`e32` | 236,00 / 3 ha = 78,67 Bs/ha, con el denominador a la vista. |
| Sindicato, Ajustes (I-50), Modo (I-51) | `e33`–`e35` | Sindicato abre el centro existente. |
| Cambio a varias personas y vuelta a individual | `e36`–`e40` | Con varias personas reaparecen Personas y «Por cobrar»; al volver, las cifras son idénticas. |
| Letra al 130 % y 200 %; horizontal | `e41`–`e45` | Sin desbordes; el riel lateral resalta Chacos. Se restauraron los ajustes del sistema. |
| Modo avión: compra al contado de 3 L × 120 | `e46`–`e48` | Guardada sin conexión: compras 2.376 Bs, deuda sin cambio, Herbicida 13 L. |
| Voz: panel, Escuchando, Cancelar | `e49`–`e51` | Sin transcripción; «Dictado cancelado: el formulario no cambió». El emulador no tiene audio real. |
| Actualización con `install -r` de la candidata final | `e52`–`e53` | Datos y modo conservados (`firstInstallTime` 19:04, `lastUpdateTime` 20:28). |

**Defectos encontrados en el recorrido y corregidos** (`9510fc6`, `b8248fb`):
- Proveedores, abierto desde Registrar, no tenía Atrás.
- Con «Sin campaña activa», Inicio mostraba una deuda de 0,00 Bs.
- Doble espacio en el aviso de compra a crédito.
- El ejemplo de voz de la compra decía «para Rosa».

## Capturas del arnés

Carpetas `orq/`, `a/`, `b/` y `c/`: app real sobre una base sintética en `flutter test`, a 1,0, 1,3 y 2,0 y a 900 dp (`tool/rediseno/capturas_ind_*_test.dart`).
