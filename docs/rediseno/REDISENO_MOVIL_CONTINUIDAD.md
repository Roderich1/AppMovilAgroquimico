# Rediseño móvil — continuidad entre sesiones

Leer esto y comprobar Git (`git -C _wt/RDM-MOB log --oneline -5`, `git status`) antes de seguir. No repetir lo ya validado sin motivo.

## Base, rama y worktree

- **Base:** `feat/etapa2-historial-colaboradores` @ `01b2576` (trabajo funcional más reciente: formulario único con voz, identificación y foto, convocatorias, historial, colaboradores, CONV-2). Comprobado el 2026-11-12: árbol limpio en `_wt/ET2-MOB` y ningún commit posterior en ninguna rama; `evidence/ui-actual-2026-11-11` (`c99123b`) sólo tiene capturas.
- **Rama:** `feat/rediseno-movil` (local, sin push).
- **Worktree:** `_wt/RDM-MOB`.
- **Último commit:** ver `git log -1`; el estado de cada bloque está abajo.
- **Prototipo:** artefacto `https://claude.ai/artifact/CddqjNWu6qNar1Xb8HZgvi` (lienzo de diseño, 56 láminas + «Hoy»). Copia de trabajo de las láminas en el scratchpad de la sesión (no versionada).
- **Inventario prototipo ↔ Flutter:** `docs/rediseno/INVENTARIO_PROTOTIPO_FLUTTER.md`.

## Bloques

| Bloque | Estado | Notas |
|---|---|---|
| 1 · estilos compartidos + compra completa | **Hecho, en revisión del autor** | Ver «Bloque 1» abajo. |
| 2 · aplicación y planificación | Pendiente | Reutilizar `agro_ui.dart`, `VoiceFormPanel` (inline o `docked`), `VoiceSlotMark(onWriteOther:)`. |
| 3 · Inicio, Actividad, Almacén, Personas | Pendiente | Incluye la barra nueva y la hoja «Registrar» (1.7). |
| 4 · Sindicato, convocatorias, identificación, fotos | Pendiente | Textos de consentimiento: los vigentes, nunca «la Directiva verá». |
| 5 · ajustes, catálogos, campañas, reportes, acceso, respaldos, confirmaciones | Pendiente | — |

## Bloque 1 — lo hecho

- **Tema** (`lib/presentation/theme/agro_theme.dart`): paleta del prototipo (verde #0F2A1D, lima #C8F04A, fondo #F2F4EE), DM Sans + Bricolage Grotesque empaquetadas (`assets/fonts/`, OFL registrada en Más › Licencias, procedencia en `assets/licenses/README.md` nota 8). Densidad compacta conservada para no mover las pantallas aún no rediseñadas. `primaryContainer` suave (#E3F6A8): el lima intenso queda para acciones.
- **Componentes** (`lib/presentation/widgets/agro_ui.dart`): `FlowTopBar`, `StepProgress`, `PillButton`, `AgroGroup`, `ValueRow`, `StatusBadge`, `SectionHeader`, `ItemCard`, `DashedAddButton`, `BottomPanel`, `TotalLine`, `PrimaryActionButton`/`SecondaryActionButton` (son `FilledButton`/`OutlinedButton`), `SegmentToggle`, `ChoiceCards`, `NoticeBox`, `InPageSheet`. `AdaptiveEntityPicker(rowStyle: true)` dibuja la fila de valor; «Limpiar» pasa a «Quitar selección» en su hoja.
- **Voz** (`voice_form_dictation.dart`, sólo presentación): `VoiceFormPanel` nuevo (anclado o en tarjeta), `VoiceResultBanner`, `VoiceMarkBadge`, revisiones con «Escribir otro valor». `VoiceFormDictation.completions` (contador) para cerrar el panel al terminar. Motores, puertos, intérprete y reglas de mezcla sin cambios.
- **Compra** (`purchase_form_screen.dart`): presentación nueva; validación, confirmación, pago y puente de voz intactos salvo: el problema de validación de una línea abre su hoja y se muestra arriba de ella (no en barra flotante); textos en «usted».
- **Pago al proveedor** (`provider_payment_fields.dart`, compartido con «Registrar pago»): «¿Cómo pagó?» y fecha como fila.

### Diferencias con el prototipo y por qué

| Prototipo | App | Motivo |
|---|---|---|
| «Guardar» / «Guardar y añadir otro» en la hoja del producto | «Listo» / «Añadir otro» | La hoja no guarda: edita el borrador. «Guardar» haría creer que la compra quedó registrada. |
| Revisión del precio con «118,00 / 180,00» | Opciones del intérprete («Por L», «Total de la línea») + «Escribir otro valor» | No se inventan alternativas (encargo §4). |
| «Lo que se entendió hasta ahora» / «Usted dijo» | Sin texto | El motor de la compra no da texto parcial; no se muestran transcripciones (privacidad, capturas). |
| «Pasando al formulario» | «Procesando tu voz» | Encargo §4. |
| Medidor «Nivel de la voz» | Icono del micrófono en lima | No hay nivel de audio disponible: un medidor sería simulado. |
| Borde de campo #B9C9BE | #7D8D82 | Contraste 3,5:1 para distinguir el campo. |
| Paso 1 sin micrófono arriba | Micrófono arriba en ambos pasos | Conserva el botón que muestra/oculta el panel (`form-dictar`). |
| Barra Inicio · Actividad · Almacén · Personas · Sindicato | Barra actual (Operaciones, Inventario, Cuentas) con el tema nuevo | Es del bloque 3. |
| «Continuar» visible con el panel de voz | Oculto mientras el panel está abierto (como la lámina 2.2) | Se vuelve con ✕; tras dictar el panel se cierra solo. |

## Verificación del bloque 1 (ver evidencia)

- Evidencia: `docs/evidence/rediseno-movil/2026-11-12/README.md`.
- Entorno propio del emulador: `tool/rediseno/rdm_env.sh` (contenedor `agro_rdm_pg` 15436, API 3370, túnel 3371/3372, paquete `.rdm` «AC RDM», cuenta sintética `agricultor15`). `tool/rediseno/rdm_ui.sh` toca por texto sólo con `.rdm` en primer plano. No toca `.demo`, `.et1` ni otras apps.
- Capturas del arnés (fuentes reales, 390×844): `flutter test tool/rediseno/capturas_arnes_test.dart` (`RDM_TEXT_SCALE=1.3`/`2.0`).

## Trampas aprendidas

- `adb input text` no admite acentos; tocar por texto falla con selectores (`excludeSemantics`): usar el rótulo («Recibe toda…», «Persona que recibe») o coordenadas.
- Con el teclado abierto, un toque en el velo cierra la hoja (el borrador se conserva).
- Android muestra un instante el último carácter de una contraseña: **no** capturar pantalla mientras se teclea una clave; si ocurre, borrar la captura (pasó el 2026-11-12 con `s2.png`, borrada en el acto, nunca usada).
- `MSYS_NO_PATHCONV=1` rompe las rutas de `node` en `rdm_env.sh credential`: no exportarla en esa orden.
- Pruebas: los campos de un producto sólo existen con su hoja abierta; usar `test/support/purchase_form_driver.dart`.

## Estado de la candidata (2026-11-12)

- Instalada en el emulador: `.rdm` con `2d6aa0d` (con modelos de voz). APK de `15bc23e`: `C:/Users/MSI/AppData/Local/Temp/agro_rdm/apk/agrocuentas.rdm-15bc23e-profile-x64.apk`; no cabe en el emulador (802 MB libres).
- Modelos de voz copiados de `_wt/F09-UNI` a `android/app/voice-models` y `jniLibs/x86_64` (ignorados por git; verificados con su manifiesto).
- Entorno: contenedor `agro_rdm_pg` y API 3370 en marcha; túnel **cerrado** al terminar. La APK está atada a ese origen: sin túnel funciona sin conexión; para sincronizar hay que abrir otro túnel y recompilar.
- Capturas del arnés: `build/rediseno_capturas` (no versionado) y copia en la evidencia.

## Pendientes concretos del bloque 1

- Revisión visual del autor.
- Hallazgo aparte (no corregido): «Deshacer último dictado» con el precio en revisión dice que se conservó la moneda. Comprobar en la base `01b2576` antes de proponer nada.
- Prueba de voz con una persona real en teléfono físico.

## Siguiente acción concreta

Esperar la revisión del autor sobre la candidata del bloque 1 (capturas antes/después y APK `.rdm`). Con su visto bueno, empezar el bloque 2 por «Nueva aplicación» paso 1 (láminas 3.1–3.2), confirmando antes el significado de «Quién aplicó».
