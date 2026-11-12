# Rediseño móvil — continuidad entre sesiones

Leer esto y comprobar Git (`git -C _wt/RDM-MOB log --oneline -5`, `git status`) antes de seguir. No repetir lo ya validado sin motivo.

## Base, rama y worktree

- **Base:** `feat/etapa2-historial-colaboradores` @ `01b2576` (trabajo funcional más reciente: formulario único con voz, identificación y foto, convocatorias, historial, colaboradores, CONV-2). Comprobado el 2026-11-12: árbol limpio en `_wt/ET2-MOB` y ningún commit posterior en ninguna rama; `evidence/ui-actual-2026-11-11` (`c99123b`) sólo tiene capturas.
- **Rama:** `feat/rediseno-movil` (local, sin push).
- **Worktree:** `_wt/RDM-MOB`.
- **Último commit:** ver `git log -1`; el estado de cada bloque está abajo.
- **Prototipo:** artefacto `https://claude.ai/artifact/CddqjNWu6qNar1Xb8HZgvi` (lienzo de diseño, 56 láminas + «Hoy»). Copia de trabajo de las láminas en el scratchpad de la sesión (no versionada).
- **Inventario prototipo ↔ Flutter:** `docs/rediseno/INVENTARIO_PROTOTIPO_FLUTTER.md`.

## Organización desde el 2026-11-12 (orquestador + sesiones A, B, C)

Desde la tarde del 2026-11-12 el trabajo se reparte entre el **orquestador** (este worktree, `feat/rediseno-movil` = rama de integración) y tres sesiones implementadoras en worktrees propios (`_wt/RDM-A`, `_wt/RDM-B`, `_wt/RDM-C`). Todo lo de coordinación (asignaciones, archivos reservados, bases publicadas, entregas integradas, mecanismo de entrega) está en **`docs/rediseno/COORDINACION.md`**; el estado de cada sesión, en `docs/rediseno/estado/<X>.md` (en su rama y, tras integrar, aquí); las revisiones del orquestador, en `docs/rediseno/revisiones/`. Una rama funcional externa (sesión F, `_wt/ET2-MOB`) aportó Excel y el consentimiento separado (integrada en B2).

Herramientas comunes, no versionadas: `ProyectoAgro/_artefactos/rediseno/` (láminas `.dc.html`, `render_laminas.sh`, `side_by_side.py`, `venv` con Pillow).

Worktree temporal `_wt/RDM-BASE` (detached en `01b2576`): sólo para comparar con la base; se puede quitar con `git worktree remove` cuando no haga falta.

## Bloques

| Bloque | Estado | Notas |
|---|---|---|
| 1 · estilos compartidos + compra completa | Hecho (orquestador) | Ver «Bloque 1» abajo. |
| 2 · aplicación y planificación (+ listas, + grupo Personas) | Hecho (sesión A) | Entregas A1–A7; `docs/rediseno/estado/A.md`. |
| 3 · Inicio, Actividad, Almacén (+ compras, transferencias, producto, avisos, estimación) | Hecho (sesión B) | Entregas B1–B5; barra y hoja «Registrar» del orquestador (B1). |
| 4 · Sindicato, convocatorias, vínculos, identificación, fotos, sincronización | Hecho (sesión C) | Entregas C1–C4 sobre la rama F. |
| 5 · ajustes, datos, campañas, reportes, modo, respaldos, acceso, PIN, tardías, confirmaciones | Hecho (orquestador) | Acceso/PIN/tardías con `AgroAppBar`; confirmaciones como diálogos con el estilo nuevo. |

**Estado (noche del 2026-11-12):** integración `feat/rediseno-movil` con todas las entregas y la rama funcional F (sin P-A); suite completa 3044/3/0 sobre `6b397c9`; **candidata `d6c4c4d`** (+ corrección de Actividad/Almacén hallada en el segundo recorrido) instalada en el AVD propio `RDM_Pixel8` (`emulator-5556`, «AC RDM»), sin túnel. Recorridos: activación, titular, campaña, compra sin conexión, persistencia, transferencia, plan, aplicación, pago, Excel, PDF, borrador. Guía para el autor: `docs/rediseno/REVISION_AUTOR.md`; comparativas en `integracion/comparativas/`. Evidencia: `docs/evidence/rediseno-movil/2026-11-12/integracion/README.md`. **Nada revisado por el usuario todavía.**

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
- ~~Hallazgo «Deshacer último dictado»~~: **corregido** el 2026-11-12 (`75361ed`): era un defecto de `01b2576` que afectaba al estado (revisión pendiente y moneda en dólares), con dos regresiones.
- Prueba de voz con una persona real en teléfono físico.

## Pendientes concretos (cierre del 2026-11-12)

1. **Revisión del autor** de la candidata (`emulator-5556`, «AC RDM» `d6c4c4d`) con `REVISION_AUTOR.md` y las comparativas; ninguna pantalla está aceptada por el usuario.
2. **Decisiones del autor anotadas (no tomadas aquí):** «Persona» en la aplicación con «Responsable del chaco · se usan sus productos» en lugar de «Quién aplicó»; CONV-3 trata de «tú» (rama F); UIBUG-023 (sin tabla en pantalla ancha de Almacén); «sólo él puede aprobar» en el texto del PIN (género, texto anterior al rediseño).
3. **`.rdm` antigua (`2d6aa0d`) en el `Pixel_8` compartido:** identificada como antigua y **no se desinstala** por ahora (indicación del autor del 2026-11-12); no usarla para revisar.
4. **f08_prev_01_previo_ui_test:** falló en 2 de 5 suites completas de la rama y pasó en las dos últimas; la prueba y el código de respaldos son idénticos a `01b2576`; bajo carga en `01b2576` pasó 3 de 3; la comparación en HEAD quedó sin hacer (se cortó por memoria). **Investigado** (`docs/rediseno/F08_PREV_01_INTERMITENTE.md`): las vueltas no cambian con carga ni entre rama y base; una retención real de ≥2 s en la acción reproduce el mismo mensaje. Causa de la retención en la suite: sin observar. **Abierto.**
5. **Intermitencias vistas en suites completas y no reproducidas aisladas:** `e2_joint_purchase_screens` (una vez), `f10_x01_pago_datos` (2 de 7 ejecuciones), `f10_x01_inicio_mas` (una vez en pareja). Patrón: esperas de vueltas fijas frente a E/S real. Sin corregir.
6. **Voz con una persona real** en un teléfono físico (precisión no medida).
7. ~~Recorrer aplicación, plan, pago, transferencia~~ (hecho, segundo recorrido). **Convocatorias con servidor, vínculos, necesidad/consumo publicados y reautenticación: bloqueados** porque abrir el túnel fue denegado por los permisos de la sesión; la sesión quedó pidiendo «Volver a autenticar» tras «Actualizar» sin servidor (previsto).
8. Foto de la etiqueta desde el detalle de Producto (solicitud 4 de B): hoy se llega por Datos › Productos › menú.
9. `RdmCPage`/`RdmAListPage`/`ScreenTitleBar` hacen lo mismo: unificarlas en `agro_ui.dart` cuando no haya sesiones trabajando (limpieza, sin cambio visual).
10. La lámina «Nuevo período histórico» corresponde a la función de **Operaciones tardías** (botón «Período histórico»), no a Campañas: se dejó con su diálogo vigente.

11. **P-A** (sustitución de responsable de convocatoria): no integrada; la sesión F la implementa (ver `COORDINACION.md`).
12. PDF «Estado de cuenta»: columnas truncadas con «…» en A4 vertical (maquetación anterior al rediseño; no se tocó).

## Siguiente acción concreta

Esperar la revisión del autor sobre la candidata integrada (`d6c4c4d` en `emulator-5556`, «AC RDM»). Si el autor abre o autoriza el túnel: recorrer convocatorias (participar, estados de envío), vínculos y publicación de consumo, y volver a autenticar. Cuando la sesión F entregue P-A: integrarla según `COORDINACION.md`. Sus correcciones se reparten por `COORDINACION.md` (las sesiones A, B y C están en espera, sin tocar sus worktrees). Para reabrir el entorno: `RDM_SERIAL=emulator-5556`, `rdm_env.sh up` (Back congelado `_wt/RDM-BE`), `rdm_env.sh tunnel` (necesita permiso), recompilar desde el mismo SHA con `build-app` e `install-app`.
