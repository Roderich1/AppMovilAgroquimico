# Bloque 1 de la revisión integral — Sindicato en palabras, español en el sistema y confirmación en Archivar

- **Fecha real:** 2026-10-27 (America/La_Paz). Sesión A, por encargo de Roderich del 2026-10-26 (frente 3, parte de sindicato, idioma y catálogos). Rama `fix/sindicato-estado-textos-localizacion` sobre `main` `a68285c`.
- **Trazabilidad:** CU-10/CU-11 (necesidad y sincronización, RF-18), RNF-07 (RU-13), INT-02; catálogos CU-02. Issue MOB #37. Contratos F05/F06 del Backend: sin cambios.

## 1. Commits

| SHA | Qué |
|---|---|
| `dffc2cf` | Sincronización: filas con producto y campaña (LEFT JOIN en la misma consulta `entries()`, por el tenant del vínculo de cada fila), estados en palabras, explicación por familia de código, «Detalle técnico» plegado (código, intentos, próximo intento), «Decidir…», sin «(403)»; texto de `SyncConflictPendingException` |
| `8f8e8fa` | Necesidad declarada y Consumo: «Guardada en el teléfono. Se enviará al sindicato; aquí verá cuándo la acepta.», estados en palabras por fila, tarjeta de aviso con «Sincronizar ahora» |
| `ddb2f11` | `flutter_localizations`, `Locale('es')`, `supportedLocales [es]`, delegados globales; pruebas con `AgroApp` adaptadas a «ACEPTAR»/«Cancelar»/«Mes anterior» |
| `c1c6d7a` | Catálogos: «Archivar» con `confirmDestructiveAction` y aviso de resultado; `archiveCatalog` sin cambios |
| `7212a0c` | Revisión cruzada: rechazos terminales de titularidad y de versión con frase propia; `AUTH_PAUSED` sin texto duplicado; «Revisar…» en rechazadas; «Se archivó X.» |
| `f4f1e64` | Fila pausada por versión: «Pausada: versión distinta de la aplicación», como la tarjeta de reanudación del PR de D-01 |

Textos de #150 conservados literalmente: «Todavía sin confirmación», «Última confirmación: fecha», «Confirmado: fecha». Worker, estados, cola, `last_code`, `summary()` y contrato sin cambios.

## 2. Pruebas de host

- `sync_screens_test` (adaptada), `sync_code_presentation_test` (nueva, 17 casos: ACK CONFLICT distinto de ACK REJECTED, titularidad aparte, `AUTH_PAUSED` sin repetir, rótulo del botón), `f10_localizacion_selector_fecha_test` (nueva: «ACEPTAR», «Cancelar», «Mes anterior» y la misma fecha civil), `catalogs_archive_confirm_test` (nueva: cancelar no archiva), `f10_sync_release_refresh_test` (dos aserciones de texto), `f10_mensajes_autorizacion_test`, `f10_sync_textos_confirmacion_test`, `consumption_publish_screen_test` → `00:15 +43: All tests passed!`; tras `f4f1e64`: `sync_code_presentation_test` + `sync_screens_test` + `f10_sync_release_refresh_test` → `00:14 +25: All tests passed!`.
- Suite completa en la rama (`c1c6d7a`, con otra suite en paralelo): 1 860 pasan, 3 omitidas, **2 fallos** en `f03_access_recovery_app_test` y `f04_admin_owner_restore_ui_test`: aislados, `f03…` pasó 3/3 de inmediato; `f04…` falló aislado una vez con la máquina cargada («Paga el titular: Titular» y «Respaldo restaurado» no encontrados dentro del presupuesto fijo de espera) y pasó 2/2 después con la máquina libre, y 4/4 para el autor; las rutas afectadas no se tocan en esta rama. Inestabilidad por presupuesto fijo de `waitFor` bajo carga, no regresión.
- `dart format` sin cambios; `flutter analyze` «No issues found!». Commits sin trailers; única dependencia nueva: `flutter_localizations` (SDK).
- **Revisión cruzada:** LISTO; ajustes 1–3 y 5 incluidos en `7212a0c`. Declarado: con `es`, el modo de teclear fecha del selector interpreta `dd/mm/aaaa` (antes `mm/dd/yyyy`); no afecta a fechas guardadas, `formatDate`, `localDay`, unidades, dinero (`es_BO` explícito) ni zona horaria. `Locale('es')` fuerza español aunque el teléfono esté en otro idioma.

## 3. Comprobación en EMULADOR (integración local de las cuatro ramas)

Ver `F10_BLOQUE1_INTEGRACION_EMULADOR.md`: tras declarar 20 L de Glifosato Demo sin acceso verificado: aviso «Guardada en el teléfono. Se enviará al sindicato; aquí verá cuándo la acepta.», fila «Glifosato Demo · Verano Demo 20 L · Guardada, pendiente de envío», tarjeta «Verifique el acceso en línea para enviar. Sus datos siguen guardados.» con «Sincronizar ahora» en la misma pantalla; al pulsarlo: `refresh 200`, `push 200`, fila «Aceptada por el sindicato: 27/10/2026». Sincronización: «Glifosato Demo · Verano Demo · Necesidad declarada · Publicar · 20 L · Aceptado por el sindicato · creada 27/10/2026 · Confirmado: 27/10/2026», chip «Última confirmación: 27/10/2026», «Detalle técnico» plegado con «Código: OK · Intentos: 1 · Envío: <uuid>». Selector de fecha: «Seleccionar fecha», «Mes anterior», «martes, 27 de octubre de 2026, Hoy», «Cambiar a cuadro de texto»; semántica del sistema en español («Desplegado», «Contraído», «Pestaña 1 de 5»). Archivar Bellator: «¿Archivar Bellator? Dejará de aparecer en las listas y formularios; su historial se conserva.» → Cancelar → el producto sigue en la lista.

## 4. Límites

Las familias de código de rechazo y conflicto se comprobaron sólo en host (requieren ACK REJECTED/CONFLICT de Central). «Sincronizado» sigue en chips e indicador del shell (`outboxStatusLabel` intacto). Sin teléfono físico.
