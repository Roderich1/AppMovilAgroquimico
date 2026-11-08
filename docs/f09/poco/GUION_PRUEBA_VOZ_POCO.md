# Guion de prueba manual de la voz en el POCO («AC F09»)

| Campo | Valor |
|---|---|
| Versión | 2026-11-08, rama `docs/f09-protocolo-guion` desde `27e9a4e`. Guion **sin ejecutar** |
| Teléfono | POCO X5 Pro 5G (`22101320G`, Android 12) |
| Quién | Roderich, con datos sintéticos de la DEMO |
| Duración estimada | 60–75 min |
| Resultados | [`RESULTADOS_PLANTILLA.md`](RESULTADOS_PLANTILLA.md) (casillas) o [`resultados_PLANTILLA.csv`](resultados_PLANTILLA.csv). Se rellena una **copia** con la fecha real, y no la plantilla |

> **Esto NO es la ejecución de #12.** Es una prueba de exploración y ajuste.
> - Las frases de este guion quedan **expuestas** y no pueden usarse como holdout ni como frases de aceptación (`../evaluacion/FRASES_Y_HOLDOUT.md` §1).
> - Sus resultados no se leen contra los umbrales de c-12.
> - No cierra #12 ni #17.
> - Lo que se observe aquí es procedencia DEVICE, sólo sobre el commit de la APK instalada.

**Qué se registra solo, sin tomar tiempos a mano:**
- Con el permiso de evaluación dado, cada borrador de voz que se cierra con al menos un dictado guarda una entrada en el teléfono:
  - texto reconocido;
  - campos propuestos;
  - correcciones;
  - campos confirmados;
  - resultado;
  - motor;
  - commit, si la APK lo lleva.
- El registro interno de la app anota el tiempo de revisión de cada frase (`revision=…ms`), sin texto.

**Lo que no se registra:** la ficha, el modelo, el primer parcial y la duración de cada frase (A15 y A16 de `../evaluacion/PREGUNTAS_CLASIFICADAS.md`). **No los mida a mano.** Basta con anotar «pasa / falla / no ejecutado» y una observación corta.

**Regla durante toda la prueba:** no restaure ningún respaldo en este teléfono mientras haya dictados guardados (M1 de `../evaluacion/COPIA_PREVIA_Y_EVIDENCIA.md`).

## Frases de EXPLORACIÓN (expuestas, no reservadas)

Productos del catálogo sintético de la DEMO. Diga el nombre completo, con «demo»: con sólo «herbicida» la app propone opciones y no elige ninguna, que es lo esperado.

| ID | Frase | Dónde |
|---|---|---|
| E1 | «Compré cinco litros de herbicida demo a ciento veinte bolivianos el litro» | Compra por voz |
| E2 | «El proveedor es agroinsumos demo» | Compra por voz |
| E3 | «Compré un litro y medio de fungicida demo a ciento cincuenta bolivianos el litro» | Compra por voz |
| E4 | «Compré tres litros de» … (pausa de unos 2 s, sin tocar «Detener») … «insecticida demo» | Compra por voz |
| E5 | «Apliqué dos litros de herbicida demo en el chaco norte demo» | Aplicación por voz |
| E6 | «Planificar el chaco norte demo con un litro por hectárea de fungicida demo» | Planificación por voz |

---

## Bloque 0. Preparación (una vez)

| # | Acción | Resultado esperado | Observado | P / F / NE |
|---|---|---|---|---|
| P1 | APK **ARM64** final de «AC F09» (2026-11-08):<br>- archivo `C:\Users\MSI\AppData\Local\Temp\agro_f09\apk_final\agrocuentas-f09-c080b9a-arm64-v8a-profile.apk`;<br>- código `c080b9ae6f6e878ff30c4b05f75ec04c7e5969ac`;<br>- SHA-256 `4dd970139d7babc34799991206460decf7e7f862bf20d1d85f1d11cdc100f181`.<br>Lleva dentro el origen del túnel abierto el 2026-11-08: **sólo sirve para activar mientras ese túnel siga abierto**. Si se cierra antes de activar, hay que recompilar desde el mismo commit con un túnel nuevo. Las APK x86_64 son para el emulador y no sirven | SHA-256 comprobado (`certutil -hashfile <apk> SHA256` en Windows) | | |
| P2 | Instale la APK, por una de estas vías:<br>- **por cable:** `adb install <apk>`; para actualizar, `adb install -r <apk>`, que **conserva los datos**. MIUI exige la pantalla encendida y desbloqueada; toque «Instalar» en «Instalar vía USB» antes de 10 s;<br>- **a mano:** copie la APK a «Descargas», ábrala con «Gestor de archivos», permita «Instalar apps desconocidas» para el gestor y toque «Instalar».<br>No desinstale «AC VOZ» ni otras instalaciones | Aparece el icono «AC F09», junto a los demás | | |
| P3 | **Con red y con el túnel abierto:** active la app con una cuenta de agricultor de la DEMO. Están ocupadas `agricultor6` («AC VOZ»), `agricultor5` («AC F09» del emulador), `agricultor2` («AC UX») y `agricultor1` («AC DEMO»). Se propone `agricultor4`: tiene historial de campañas en el Central, pero esta prueba no sincroniza nada y activar no lo cambia. Con el POCO conectado por cable, la contraseña de un solo uso la teclea la herramienta en el campo enfocado (`demo.sh credential agricultor4 <serie del POCO>`) y **no se anota aquí**. Cree el titular con un nombre sintético, en modo **Compartido** | Activación correcta. Es el único paso que necesita red | | |
| P3b | **Atajo con cable** (en lugar de P4): con el POCO conectado y la app detenida, la coordinadora puede cargar los mismos datos sintéticos que el emulador (`F09_SERIAL=<serie> tool/f09_emu/f09emu.sh sembrar agricultor4`): personas DEMO, compras, existencias de Herbicida, Fungicida e Insecticida DEMO, chaco y campaña activa | Inventario con existencias de los tres productos | | |
| P4 | Sin cable: cree los datos sintéticos mínimos (en Catálogos y Campañas, o con «Crear…» en los selectores):<br>- proveedor «Agroinsumos DEMO»;<br>- productos «Herbicida DEMO», «Fungicida DEMO» e «Insecticida DEMO», en litros;<br>- chaco «Chaco Norte DEMO», del titular, 3 ha (30 000 m²);<br>- campaña «Invierno 2026 (DEMO)», **activa**;<br>- con el formulario manual, una compra de **10 L de Herbicida DEMO** para tener existencias | Todo visible en sus listas. Inventario: Herbicida DEMO 10 L | | |
| P5 | Más → Registrar por voz → **Evaluación de la voz**. Lea el texto y toque «Acepto». El texto todavía es una **propuesta**: en esta prueba sólo participa usted, con datos sintéticos | «Permiso: dado. Dictados guardados: 0» | | |
| P6 | **Modo avión.** Abra el Centro de control (deslice desde la esquina superior derecha) y active «Modo avión».<br>Compruebe que el Wi‑Fi y los datos móviles quedan apagados: MIUI puede dejar el Wi‑Fi encendido; si es así, apáguelo.<br>Compruebe en la barra de estado el avión, sin Wi‑Fi ni señal. Abra el navegador: no carga ninguna página | Teléfono sin red | | |
| P7 | Más → Registrar por voz → Compra por voz. La primera vez, la app copia y verifica el modelo: puede tardar unos segundos | «Reconocedor: modelo de voz de la aplicación», «Funciona sin conexión…», «Modo avión: activado.». Si el APK trae la revisión, aparece el interruptor «Revisar cada frase». Si sale «El modelo de voz de la aplicación no está disponible…», anótelo y pare | | |
| P8 | Más → **Licencias**, si la compilación ya la trae (la añade otra sesión) | Aparecen Vosk, JNA, el modelo Vosk `small-es-0.42`, whisper.cpp/ggml y el modelo Whisper. Si no está la entrada: NE | | |

---

## Bloque A. Compra: revisar, corregir, cancelar, confirmar

Sin red durante todo el bloque. «Revisar cada frase» como usted la use normalmente; anote cuál.

| # | Acción | Resultado esperado | Observado | P / F / NE |
|---|---|---|---|---|
| A1 | En Compra por voz, toque «Hablar», diga **E1** y toque «Detener» | Mientras habla, texto provisional con «Escuchando (todavía puede cambiar)». Al detener, el texto pasa a «Ya aplicado al borrador» y aparece la línea Herbicida DEMO, **5 L**, **120 Bs/L** | | |
| A2 | «Hablar», **E2**, «Detener» | Proveedor «Agroinsumos DEMO» | | |
| A3 | Revise el texto reconocido frente a los campos. Cambie **a mano** la cantidad de 5 a **4** | La cantidad queda en 4 L, marcada como corregida a mano | | |
| A4 | «Hablar», repita **E1**, «Detener» | La cantidad **sigue en 4 L**: lo dictado no sobrescribe lo corregido a mano | | |
| A5 | Toque Atrás o «Cancelar» y confirme «Descartar» en «¿Descartar el borrador?» | Vuelve atrás. Operaciones → Compras: **ninguna compra nueva**. Inventario: Herbicida DEMO sigue en 10 L | | |
| A6 | Abra otra vez Compra por voz y repita A1–A3 | El borrador empieza vacío. Queda la línea de 4 L con el proveedor | | |
| A7 | En «¿Ya pagaste al proveedor?», elija **«Sí, pagué todo»** | «Paga el titular: …», con el importe, el medio y la fecha visibles. «Registrar compra» se habilita | | |
| A8 | Toque «Registrar compra» **una vez** | Vuelve atrás. No se abre ningún diálogo de descarte (#120) | | |
| A9 | Compruebe los efectos | Compras: **una sola** compra nueva, Agroinsumos DEMO, Herbicida DEMO 4 L, 480 Bs, **pagada**. Inventario: Herbicida DEMO 14 L, con un lote nuevo. Evaluación de la voz: «Dictados guardados» subió en 2 (el borrador descartado y el confirmado) | | |

---

## Bloque B. Continuidad y casos difíciles

| # | Acción | Resultado esperado | Observado | P / F / NE |
|---|---|---|---|---|
| B1 | Abra una nueva Compra por voz justo después de cerrar la anterior | Borrador y «Ya aplicado al borrador» vacíos. Nada del dictado anterior | | |
| B2 | «Hablar», **E3**, «Detener» | Fungicida DEMO, **1,5 L** (no 1 L), 150 Bs/L. El producto **no** es «y medio de fungicida demo» | | |
| B3 | En el mismo borrador, «Hablar» y diga **E4** con la pausa; después, «Detener» | Una línea Insecticida DEMO, **3 L**. Si queda «Falta el producto: dígalo o elíjalo.», anótelo | | |
| B4 | «Hablar» y **no diga nada** durante unos 10 s; después, «Detener» | No llega texto y el borrador no cambia | | |
| B5 | Escriba a mano el precio del insecticida (90 Bs/L) y elija el proveedor. En «¿Ya pagaste al proveedor?», elija **«No, todavía no»**. Toque «Registrar compra» | Una compra con 2 líneas, 225 + 270 = **495 Bs**, **sin pagar**. La deuda con Agroinsumos DEMO aumenta en 495 Bs. Inventario: +1,5 L de fungicida y +3 L de insecticida | | |
| B6 | Abra Compra por voz, toque «Hablar» y, mientras dice «Abriendo el micrófono», toque **«Cancelar»** | Vuelve al estado inicial sin error, y «Hablar» funciona otra vez. Si la apertura es demasiado rápida para cancelarla: NE | | |
| B7 | Salga. En Ajustes → Aplicaciones → Administrar aplicaciones → AC F09 → Permisos de aplicaciones → Micrófono, elija **Denegar**. Vuelva a Compra por voz y toque «Hablar» | «Permiso de micrófono denegado» y el texto «Sin permiso de micrófono no se puede dictar…». **No** se queda en «Abriendo el micrófono» (#119) | | |
| B8 | Toque «Usar el formulario manual» y registre a mano 1 L de Herbicida DEMO a 120 Bs, «Sí, pagué todo». Después, vuelva a **permitir** el micrófono en Ajustes | El formulario se abre vacío y la compra se registra una vez. «Dictados guardados» **no** sube: no hubo dictado | | |

---

## Bloque C. Aplicación y planificación

Antes de empezar, Inventario debe mostrar Herbicida DEMO con al menos 2 L.

| # | Acción | Resultado esperado | Observado | P / F / NE |
|---|---|---|---|---|
| C1 | Más → Registrar por voz → Aplicación por voz. «Hablar», **E5**, «Detener» | Chaco Norte DEMO, con el titular como persona (el dueño del chaco), y Herbicida DEMO **2 L**. Sin aviso de existencias | | |
| C2 | Cambie **a mano** la cantidad a **1,5 L** | Queda marcada como corregida a mano | | |
| C3 | Cancele y confirme «Descartar» | Aplicaciones: ninguna nueva. Inventario de Herbicida DEMO sin cambios | | |
| C4 | Repita C1 y C2, y toque «Registrar aplicación» una vez | **Una** aplicación de 1,5 L de Herbicida DEMO en Chaco Norte DEMO. Inventario: −1,5 L | | |
| C5 | Planificación por voz. «Hablar», **E6**, «Detener» | Chaco Norte DEMO, 3 ha, Fungicida DEMO a **1 L/ha**, requerido **3 L** | | |
| C6 | Cambie **a mano** la dosis a **2 L/ha** | El requerido pasa a 6 L, marcado como corrección manual | | |
| C7 | Cancele y confirme «Descartar» | Planificación: ningún plan nuevo | | |
| C8 | Repita C5 y C6, y toque «Crear plan» una vez | **Un** plan pendiente en Planificación, con 2 L/ha y 6 L | | |

---

## Cierre

| # | Acción | Resultado esperado | Observado | P / F / NE |
|---|---|---|---|---|
| Z1 | Más → Registrar por voz → Evaluación de la voz. Anote «Dictados guardados: N» | N = 2 (A) + 1 (B5) + 2 (C1–C4) + 2 (C5–C8) = **7**. B6 y B8 no guardan; B4 tampoco, si no llegó texto. Si N difiere, anótelo: no es un error en sí | | |
| Z2 | Decida qué hacer con lo guardado:<br>- **«Retirar el permiso» → «Retirar y borrar»**, que borra todo;<br>- o conservarlo para revisarlo; en ese caso, bórrelo después dentro del plazo que usted fije (A19) | Con la retirada: «Permiso: no dado. No se guarda nada.» | | |
| Z3 | Desactive el modo avión y vuelva a encender el Wi‑Fi y los datos | El teléfono vuelve a tener red | | |

**Qué entregar:**
- la copia rellena de la plantilla, con la fecha real, el commit y el SHA-256 de la APK;
- sus observaciones, **sin copiar las transcripciones**.

Con eso, la coordinadora redacta la evidencia DEVICE de esta exploración.
