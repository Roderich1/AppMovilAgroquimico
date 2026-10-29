# Bloque 2 · E-12: PIN del titular dentro de la activación (HOST)

- **Tipo:** HOST, sólo pruebas de Flutter en el ordenador. **No** es evidencia en dispositivo ni en emulador.
- **Fecha real:** 2026-10-27 (America/La_Paz). Horas reales de los commits y de las corridas:
  - primera ronda: commits de 13:43:45 (`e5bcd0a`) a 14:31:17 (`19b7799`); corrida de base hacia las 13:59 y corrida con el cambio hacia las 14:30;
  - segunda ronda: commit `9670558` y pruebas de 15:03:05 a 15:09.
- **Entorno:** Windows 11 Home; Flutter 3.47.2 (stable, `d3b14c8769`); sqflite_common_ffi en memoria. Sin teléfono ni emulador.
- **Decisión:** del autor, Roderich Rendón, 2026-10-27 (`_briefs/BLOQUE2_DECISIONES_AUTOR_2026-10-27.md`, E-12). Contrato: `docs/architecture/F03_RECUPERACION_IDENTIDAD_LOCAL.md` §4 y §4 bis.
- **Trazabilidad:** RF-01, RF-13, RF-03, CU-01 y RNF-04.

## Commits (rama `feat/e12-pin-en-activacion`)

| SHA | Qué |
|---|---|
| `ed9c55c` | Base: Mobile `main` |
| `e5bcd0a` | Diseño del §4 bis (fase 1) |
| `8986c19` | Ajustes H1–H10 de la revisión cruzada y resoluciones C-1…D-5; aviso de obsoleto en `docs/12_AUTHENTICATION.md` |
| `e3af008` | Implementación y pruebas nuevas |
| `19b7799` | Primera versión de esta evidencia y precisiones del §4 bis |
| `9670558` | Ajustes de la segunda revisión cruzada (commit «pendiente de verificación»; verificado abajo) |
| este commit | Evidencia de la segunda ronda |

## Qué se comprobó

| Caso de la decisión | Pruebas (archivo: nombre abreviado) | Resultado |
|---|---|---|
| Camino feliz: PIN tras confirmar al titular, sin contraseña ni red | `e12_activation_evidence_test`: U1 (consumo y emisión real); `e12_pin_offer_screen_test`: U1/E1 en host | Pasa. Después de la activación no hay ninguna petición HTTP nueva; el PIN creado autoriza |
| Identidad diferente | U2 (cuenta, Member, tenant, sesión, registro, sin sesión, otro vínculo, vínculo archivado, vínculo de otro Member); T1 (salir de la sesión); pantalla T1 (otra sesión guardada) | Pasa: sin comprobante y sin escribir el almacén |
| Instalación diferente | U3 | Pasa |
| Acreditación vencida | U4 (reloj de pared, cronómetro, reloj atrasado, `notAfter`); pantalla T3 | Pasa |
| Reuso | U5; U1 de la emisión real (segunda retirada vacía) | Pasa |
| Cancelación | U6/H2; pantalla «Ahora no» (T5/E2) y Atrás (T5); W8 (salir de «Titular de los datos» sin vincular) | Pasa; después, `/titular/pin` pide el correo y la contraseña |
| Fallo de red | U9 (la activación falla y no hay acreditación); W2 (fallo de red al configurar desde una operación) | Pasa |
| Retorno a la operación pendiente (reversión) | W1/E3 en host, W2, W3, W5, W6 | Pasa: vuelve a la revisión con el motivo escrito y editable; no llama al repositorio hasta poner el PIN y «Autorizar» |
| Retorno a la operación pendiente (tardía) | W4/E3 en host | Pasa: pide el PIN, cancelar la deja `PENDING`, nunca se confirma sola |
| Invalidación al restablecer | W7 | Pasa: tras restablecer por la vía con contraseña, la autorización emitida con el PIN de la activación se rechaza |
| PIN existente del titular (H1, D-3) | U12 (enrolled, locked, requiresOnlineReset; con otro Member o ilegible sí se enrola); T17; pantalla T10 | Pasa |
| Base histórica y otros orígenes (H2, H7, T9, T18, T20) | U11/T9/T18; U14/T20 | Pasa: no se emite |
| Segundo plano (H3, T16) | U13/T16; pantalla T16 | Pasa: `hidden` y `paused` la anulan, `inactive` no |
| Recreación del Notifier (H6, T19) | U8/T19 | Pasa |
| Restauración (H4, T7) | U10/T7 (GuardedRestore) y U10 (otro `boundAt`) | Pasa |
| Dependencias ausentes (H8) | «acceso que no es activated, o dependencias ausentes» | Pasa |
| Separación de secretos | «Separación de secretos y nada legible en textos» | Pasa: el almacén sólo tiene `verifier` y `attempts`, sin el PIN ni la contraseña; los objetos nuevos se imprimen redactados |

Archivos nuevos: `test/e12_activation_evidence_test.dart` (22 pruebas), `test/e12_pin_offer_screen_test.dart` (8) y `test/e12_pending_operation_return_test.dart` (7), con `test/support/e12_activation_harness.dart`.

## Comandos y salidas (resumidas)

Todas las órdenes se ejecutaron en `_wt/A-E12`. No se corrió la suite completa: sólo los archivos relevantes, porque otros frentes comparten la máquina.

**Base.** Sobre `8986c19`, cuyo código es idéntico a `ed9c55c`, con los 23 archivos existentes de PIN, activación, F03, F04 (reversión y tardías), F08 y titular:

```
flutter test --concurrency=2 --reporter=compact test/f03_local_owner_credential_test.dart test/f03_owner_online_confirmation_test.dart test/first_activation_coordinator_test.dart test/first_activation_screen_test.dart test/f03_access_recovery_test.dart test/f03_access_recovery_app_test.dart test/f04_owner_binding_test.dart test/f04_rf03_late_screen_test.dart test/f04_rf03_late_operations_test.dart test/f04_rf13_reversal_audit_test.dart test/f04_rf13_reversal_backup_test.dart test/f08_recovery_key_owner_pin_test.dart test/f08_recovery_key_screen_test.dart test/f08_backup_keyring_test.dart test/f04_activation_app_policy_test.dart test/f04_admin_owner_restore_ui_test.dart test/operation_mode_onboarding_test.dart test/destructive_actions_test.dart test/rec_050_reversal_rules_test.dart test/purchases_access_test.dart test/f04_restore_authorization_test.dart test/f10_mensajes_autorizacion_test.dart test/f04_installation_access_test.dart
01:04 +240: All tests passed!
```

**Con el cambio.** Sobre `e3af008`, con esta evidencia sin commitear y sólo el nombre de una prueba nueva cambiado. Los mismos 23 archivos y los 3 nuevos:

```
flutter test --concurrency=2 --reporter=compact <los 23 archivos anteriores> test/e12_activation_evidence_test.dart test/e12_pin_offer_screen_test.dart test/e12_pending_operation_return_test.dart
01:30 +277: All tests passed!
```

Son 240 existentes y 37 nuevas. En la salida no aparece ninguno de los valores de prueba de contraseña, token ni PIN (búsqueda con `grep`: 0 coincidencias para cada uno).

**Formato y análisis:**

```
dart format --output=none --set-exit-if-changed lib <pruebas e12 y su soporte>
Formatted 149 files (0 changed)        (salida 0)
flutter analyze
No issues found!
```

## Mutaciones

Script de un solo uso en el directorio temporal de la sesión. Cada mutación se aplica sobre `e3af008`, se corre su prueba (`flutter test --plain-name ...`) y se restaura el archivo con `git checkout`. Se distingue una mutación que no compila de un fallo de aserción. La primera versión de M10 no compilaba; se sustituyó por una equivalente que compila (nunca llamar a `revalidate`).

| Mutación | Prueba | Resultado |
|---|---|---|
| M1 sin comparar `sessionId` | U2 | Detectada (falla una aserción) |
| M2 sin vencimiento | U4 | Detectada |
| M3 sin retirar la acreditación al consumirla | U1 de la emisión real | Detectada |
| M4 sin comprobar el vínculo vigente | U10 | Detectada |
| M5 sin la comprobación 7 (H1) | U12 (H1) | Detectada |
| M6 GuardedRestore sin anular (H4) | U10/T7 | Detectada |
| M7 sin anular en `hidden`/`paused` (H3) | U13/T16 | Detectada |
| M8 sin la lectura directa del vínculo (H7) | U11/T9/T18 | Detectada |
| M9 retorno sin volver a la revisión | W1 | Detectada |
| M10 retorno sin revalidar la operación | W3 | Detectada |

Tras las mutaciones, `git status` sólo muestra los documentos de esta entrega: el código queda como en `e3af008`.

## Pruebas existentes

- **Ninguna prueba existente cambió sus aserciones ni su resultado esperado.** Las 240 pasan en la base y con el cambio.
- Por qué siguen igual:
  - en las pruebas que activan dentro de la app (`first_activation_screen_test`), la credencial usa el almacén Android real, que en el ordenador lanza una excepción; según H8, sin estado legible no hay oferta, y la app sigue al Inicio como antes;
  - las que montan «Titular de los datos» sin activar no tienen acreditación;
  - F08 llama al retorno sin sus avisos propios, de modo que conserva su único mensaje.

## Textos de pantalla

**Oferta del PIN** (`/titular/pin/activacion`):
- Título: «PIN del titular».
- Encabezado: «Titular vinculado. Usa inventario compartido; puede cambiarlo en Operaciones › Más › Modo de uso.» (o su variante para el inventario propio, o el aviso de modalidad no cambiada).
- «Le recomendamos crear ahora el PIN del titular. Con él, el titular autoriza en este teléfono, incluso sin conexión, las acciones que sólo él puede aprobar: revertir una operación o revisar una operación tardía.»
- «Acaba de confirmar su cuenta en línea, así que ahora no hace falta volver a escribir la contraseña. Si lo deja para después, tendrá que confirmar la cuenta en línea con su correo y su contraseña.»
- «El PIN no se guarda en el respaldo y no sirve para descifrar copias: la clave de recuperación del respaldo es otra. Tampoco reemplaza la contraseña de su cuenta.»
- «Elija un PIN de 6 dígitos que no sea una secuencia.», con los campos «PIN» y «Repita el PIN» y los botones «Crear PIN» y «Ahora no».
- Éxito: «PIN del titular creado. Funciona sin conexión.», con «Continuar».
- «Ahora no» o Atrás: «Puede crear el PIN más tarde en Operaciones › Más › PIN del titular. Entonces se le pedirá confirmar su cuenta en línea.»
- Vencida o anulada: «Ya no se puede crear el PIN con la confirmación de la activación: pasó el tiempo, salió de la aplicación o cambió la cuenta, la instalación o el titular. Puede crearlo más tarde en Operaciones › Más › PIN del titular, confirmando su cuenta en línea.»
- PIN ya existente: «Ya hay un PIN del titular en este teléfono. Para cambiarlo, confirme su cuenta en línea en Operaciones › Más › PIN del titular.»
- Fallo al guardar: «No se pudo guardar el PIN. Puede crearlo más tarde en Operaciones › Más › PIN del titular, confirmando su cuenta en línea.»

**Retorno a la operación:**
- Encabezado de la revisión y del diálogo del PIN: «PIN del titular configurado. Revise la operación y autorícela con su PIN.» (segunda ronda; antes, «PIN del titular creado. Revise la operación y confírmela con su PIN.»).
- Volver sin PIN: «No se configuró el PIN. La operación no cambió.»
- Operación ya resuelta: «Esta operación ya no está pendiente: ya fue revertida. No se hizo ningún cambio.» (o «ya se resolvió», «ya no existe», «la clave activa cambió»).
- Titular distinto: «El titular de estos datos cambió. No se hizo ningún cambio.»
- La revalidación falla (lanza): «No se pudo comprobar la operación. No se hizo ningún cambio.» (segunda ronda).
- Sin titular vinculado: «Esta acción la autoriza sólo el titular con su PIN. Para habilitarla, active la aplicación, elija el titular y configure el PIN.», sin el botón «Configurar PIN».

## Segunda ronda: ajustes de la revisión cruzada de la implementación

Revisión cruzada de `ed9c55c..19b7799`: «LISTO CON AJUSTES», sin bloqueantes. Ajustes aplicados en `9670558`:

1. **Vencimiento por reloj de pared aislado.** U4 tiene un caso con 10 min 1 s sólo en el reloj de pared y el cronómetro en cero.
2. **Pruebas de retorno nuevas:**
   - W1b, reversión de una aplicación;
   - W1c, reversión de una transferencia;
   - W3b, tardía resuelta mientras se configuraba el PIN;
   - W5b, titular cambiado (`ownerChanged`);
   - W3c, `revalidate` que lanza;
   - W2c, `requiresOnlineReset` → «Configurar PIN» → restablecer con contraseña sintética → revisión sin ejecutar;
   - F08 en dos pruebas: misma `keyId` y clave cambiada, en las dos con un solo aviso, el de F08.
3. **`owner_setup_screen.dart`:** la acreditación se anula en todo retorno sin oferta, también si la pantalla se desmonta después de vincular. Prueba W8b.
4. **Texto propio** cuando `revalidate` lanza.
5. **Encabezado del retorno** neutro, porque también sirve para restablecer, rechazar y F08.
6. **El comprobante de activación** guarda `bindingId` y `personId`, y `_requireProof` los compara. Prueba «comprobación 5 en la credencial».
7. **Documentos:** las horas reales; la mutación «no retirar» alineada (la detecta la U1 de la emisión real, no la U5, que usa un doble); y los SHA.

En la primera corrida de la segunda ronda, W1c y W3b fallaban por causas de la prueba, no del código:
- **W1c:** con la transferencia ya revertida, la fila de la lista desborda a 500 px de ancho. Es un defecto de `transfers_screen.dart` fuera de E-12, que el coordinador registra aparte. La prueba termina ahora en «Cancelar» del diálogo del PIN; el camino de autorizar ya lo cubre la compra.
- **W3b:** la actualización directa violaba un CHECK de la tabla. La versión siguiente, con `verify` y `rejectLateOperation` dentro de `tester.runAsync`, se colgó (más de 10 minutos). Se sustituyó por la actualización completa de la fila resuelta. Las pruebas nuevas no tienen bucles sin límite: todos están acotados a 40 o 60 vueltas.

**Proceso colgado.** El worktree `_wt/A-E12` quedó con un `flutter_tester` colgado de esa corrida: PID 40708, arrancado a las 14:48, con su `dart.exe` padre PID 40952. Retiene `build/native_assets/windows/sqlite3.dll`. **No se terminó**: el control de permisos lo rechazó y la regla es no eludirlo. Por eso las pruebas de esta ronda se corrieron en el worktree aparte `_wt/A-E12-T`:
- `git worktree add --detach ../A-E12-T HEAD`, sobre `9670558`, y `flutter pub get`;
- sin editar código, salvo las dos mutaciones temporales, restauradas con `git checkout`. `git status` queda limpio al final;
- cada `flutter test` con `--timeout 120s`. Ninguna prueba agotó el plazo.

**Salidas en `_wt/A-E12-T` sobre `9670558`** (orden: `flutter test --timeout 120s --concurrency=2 --reporter=compact|expanded <archivos>`, tandas de tres archivos como mucho):

| Tanda | Archivos | Salida |
|---|---|---|
| 1 (15:03:05–15:04:31) | `e12_activation_evidence_test`, `e12_pin_offer_screen_test`, `e12_pending_operation_return_test` | `01:07 +47: All tests passed!` (las 37 de la primera ronda y 10 nuevas) |
| 2 (15:05:01–15:05:19) | `first_activation_screen_test`, `f08_recovery_key_owner_pin_test`, `operation_mode_onboarding_test` | `00:14 +38: All tests passed!` |
| 3 (15:05:36–15:05:48) | `f04_rf03_late_screen_test`, `rec_050_reversal_rules_test`, `f04_owner_binding_test` | `00:08 +22: All tests passed!` |
| 4 | `f03_local_owner_credential_test`, `f03_owner_online_confirmation_test`, `f04_activation_app_policy_test` | `00:12 +42: All tests passed!` |
| 5 | `f04_admin_owner_restore_ui_test`, `destructive_actions_test`, `f04_rf13_reversal_audit_test` | `00:22 +27: All tests passed!` |
| 6 | `f10_mensajes_autorizacion_test`, `f08_recovery_key_screen_test`, `purchases_access_test` | `00:08 +11: All tests passed!` |

Las tandas 4 a 6 cubren el resto de las pruebas existentes que tocan lo cambiado en esta ronda: la credencial, la pantalla del PIN y la del titular. No se cambió ninguna aserción existente.

**Mutaciones nuevas** (15:08:45–15:08:53, mismo método que M1–M10, con `--timeout 120s`, cada una restaurada sin commit):

| Mutación | Prueba | Resultado |
|---|---|---|
| M11 quitar `now.difference(issuedAt) <= lifetime` de `isFresh` | U4 (caso «sólo reloj de pared») | Detectada: `Expected: null`, `Actual: OnlineOwnerProof(redacted)` |
| M12 `_requireProof` sin comparar `bindingId` ni `personId` | «comprobación 5 en la credencial» | Detectada: `Expected: throws CredentialException`, `Actual: Future<void>` |

**Formato y análisis** en `_wt/A-E12-T`:
- `dart format --output=none --set-exit-if-changed lib <pruebas e12 y su soporte>` → `Formatted 149 files (0 changed)`, salida 0;
- `flutter analyze` → `No issues found!`.

**Procesos.** Al terminar sólo sigue el PID 40708 antiguo. Los `flutter_tester` que aparecieron durante la ronda eran de las propias tandas, que se cerraron al acabar, o de otro frente (`e15_*`, arrancados a las 15:06). Esta ronda no dejó ningún proceso colgado nuevo.

## Pendiente y límites

- **EMULADOR, 2026-10-28** (`docs/evidence/F10_BLOQUE2_EMULADOR_2026-10-28.md`, APK de la composición `e5ba07c`, con el mismo código de E-12 que esta rama):
  - **ejecutados:** E1 (oferta, PIN sin contraseña y reversión autorizada sin red), E2 («Ahora no» y, después, PIN con contraseña) y E3 desde una reversión (vuelve a la revisión sin ejecutar);
  - **no ejecutados:** E3 desde una tardía, porque la siembra no tiene campaña cerrada (cubierto en host, W4/W3b); E4, porque la mediana no se mide sin personas. La vigencia sigue en 10 minutos (D-1).
- **Límites declarados** (§4 bis.7):
  - otra persona con el teléfono dentro de la ventana (T13);
  - sesión revocada, o cuenta o rol cambiados en el servidor dentro de la ventana, porque el paso no consulta la red (T14, T21);
  - la frontera es el código del proceso (§8): el código dentro de la app puede construir sus propios objetos.
- **En el ordenador:**
  - el cronómetro monotónico y el ciclo de vida se simulan: el reloj y el cronómetro son manuales, y el ciclo de vida llega por el canal `flutter/lifecycle`;
  - la sesión guardada se simula con un lector inyectado, y la credencial usa 1000 iteraciones de PBKDF2.
  - En el teléfono, el almacén Android y las 210 000 iteraciones no se probaron aquí.
- **Datos:** los valores de contraseña, token y PIN de las pruebas son sintéticos. Ningún archivo de esta entrega contiene credenciales reales.
- **Gate y Project:** sin cambios. Nada se publicó (sin push ni GitHub).
