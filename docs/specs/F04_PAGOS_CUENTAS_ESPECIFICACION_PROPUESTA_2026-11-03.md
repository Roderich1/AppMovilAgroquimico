# F04 · Pagos a proveedores y cuentas entre personas: especificación verificable propuesta

- **Estado:** Propuesta para revisión del autor y del tutor; no aprobada. No sustituye ni modifica el documento entregado, y no cambia ningún gate, issue ni campo del Project.
- **Fecha:** 2026-11-03.
- **Base:** Mobile `main` `5b5b318` (repositorio `Roderich1/AppMovilAgroquimico`). Las líneas de código citadas son de esa base.
- **Issues:** Refs #45 («[EI-03][REC-009][MOB] Pagos a proveedores») y Refs #49 («[EI-03][REC-013][MOB] Cuentas, pagos, adelantos y saldos»). Las dos siguen cerradas como NOT_PLANNED con Evidence = Partial; esta propuesta es la «especificación pendiente» que anuncian sus comentarios de conciliación del 2026-10-31.
- **Documento de referencia:** capítulo III de `Proyecto_Grado_Rodrigo_Univalle_v1.22.1_DEPURADO.docx`, leído como texto. En adelante, «el documento».
- **Ubicación:** `docs/specs/` es una carpeta nueva. No se usó `docs/architecture/`, porque allí viven los contratos y diseños que ganan frente a un brief (`F04_*`, `D04_E15_*`), y una propuesta no aprobada no debe confundirse con un contrato. Tampoco se numeró como documento de la serie `docs/00`–`46`, que describe la línea base.

## 1. Criterio

1. Cada regla describe **comportamiento ya implementado** en `5b5b318` o una **decisión ya tomada**: D-04 y E-15 son decisiones del autor, Roderich Rendón, del 2026-10-27; la regla del pagador es la del piloto X01 del 2026-10-26. No se proponen reglas nuevas de comportamiento; lo que falta se lista como pregunta abierta (§6.3).
2. Los criterios Q-1 a Q-5 de `docs/architecture/D04_E15_CUENTAS_IMPUTACION_Y_COSTO_PROPIO.md` §7 los fijó el coordinador para aplicar D-04 y E-15, y el autor puede revisarlos. Donde una regla depende de uno de ellos, se indica.
3. No se atribuye aprobación al tutor ni a la Directiva.
4. **Dos numeraciones distintas.** «RN-nn (repo)» es la numeración de `docs/15_BUSINESS_RULES.md`, extraída del código. «RN-nn (doc.)» y los demás RU/RF/RNF/CU/DAT son del documento v1.22.1. Un mismo número **no** designa la misma regla (§5). La trazabilidad sólo usa IDs del documento cuando el requisito existe de verdad; si no existe, se escribe «sin requisito equivalente en el documento».
5. Procedencia de la evidencia: **HOST** (pruebas `flutter test` en Windows con `sqflite_common_ffi`), **EMULADOR** (AVD Pixel_8) y **DEVICE** (teléfono físico). Un emulador no acredita un dispositivo.

## 2. Pagos a proveedores (PAG)

Contexto común: instalación activada con titular vigente (`owner_bindings` sin `ended_at`), campaña activa y una compra confirmada de total *T* en centavos de Bs, con pagos no revertidos que suman *P*.

### PAG-01 · El importe es positivo
- **Dado** una compra activa, **cuando** se registra un pago al proveedor con importe ≤ 0, **entonces** se rechaza con «El pago debe ser mayor a cero.» y no se escribe nada.
- **Código:** `lib/data/agro_repository.dart:1247-1248`; además `CHECK(amount_bob_minor > 0)` en `provider_payments` (`lib/data/app_database.dart:576-578`).
- **Regla repo:** RN-16 (repo), apartado «Además».

### PAG-02 · El pago no supera el saldo de la compra
- **Dado** una compra activa con *P* pagado, **cuando** se registra un pago *A* con *P* + *A* > *T*, **entonces** se rechaza con «El pago supera el saldo de la compra.» y no se escribe nada.
- **Dado** lo mismo, **cuando** *P* + *A* ≤ *T*, **entonces** el pago (parcial o total) se guarda.
- **Código:** `agro_repository.dart:1299-1309` (suma sólo los pagos con `reversed_at IS NULL`). La pantalla precarga el saldo y muestra «Máximo …» (`lib/presentation/screens/purchases_screen.dart:66-75, 384`), pero la regla la aplica el repositorio.
- **Regla repo:** RN-16 (repo).

### PAG-03 · Una compra revertida no acepta pagos
- **Dado** una compra revertida (`reversed_at` no nulo), **cuando** se intenta registrar un pago, **entonces** se rechaza con «La compra no está activa.» y no se escribe nada.
- **Código:** `agro_repository.dart:1282-1289`. La lista de Compras no ofrece «Registrar pago» en una compra revertida (`purchases_screen.dart:246`).
- **Regla repo:** RN-16 (repo), apartado «Además».

### PAG-04 · Fecha y medio del pago
- **Dado** una compra activa, **cuando** el pago lleva una fecha posterior a hoy, **entonces** se rechaza («… Un pago ya hecho no puede tener una fecha futura. No se registró nada.») sin escribir la compra ni el pago.
- **Cuando** la fecha es anterior a la compra (anticipo al proveedor), **entonces** se admite tal cual.
- El medio se guarda como lo indicó la persona (`CASH`, `TRANSFER` o `UNSPECIFIED` = «Sin indicar»).
- Sólo se juzgan los pagos nuevos; los guardados no se reescriben.
- **Código:** `agro_repository.dart:1290-1298`; `PaymentMethod` en `lib/domain/models.dart`.
- **Regla repo:** RN-16 (repo), «Desde el 2026-10-26».

### PAG-05 · Registra el pago el titular vigente
- **Dado** una instalación en cualquier modalidad, **cuando** se registra un pago al proveedor a nombre de otra persona (familiar, tercero o ADMIN que no es titular), **entonces** se rechaza sin cambios.
- **Cuando** no hay titular vinculado, **entonces** se rechaza.
- Los pagos históricos registrados por otra persona no se reasignan.
- **Código:** `agro_repository.dart:1058-1072` (`_requireOwnerPayer`, leído en la misma transacción) y `1250-1255`.
- **Regla repo:** RN-16 (repo) («el pagador es el titular vigente»).

### PAG-06 · Compra y pago en una sola transacción
- **Dado** una compra nueva confirmada con «Sí, pagué todo», **cuando** se guarda, **entonces** la compra y su pago por el total se escriben en la misma transacción.
- **Cuando** el pago es inválido (por ejemplo, fecha futura o sin titular), **entonces** no queda ni la compra ni el pago.
- **Código:** `agro_repository.dart:1016-1050`.

### PAG-07 · El pago al proveedor no altera las cuentas entre personas
- **Dado** cualquier estado de cuentas, **cuando** se registra un pago al proveedor (posterior o con la compra), **entonces** sólo se inserta una fila en `provider_payments`: `account_transactions` y `payment_allocations` no cambian.
- «Pagado proveedores» de Inicio se suma aparte de «Pagos recibidos».
- **Código:** `agro_repository.dart:1310-1316` (única escritura de `_insertProviderPayment`); `dashboard()` suma `provider_payments` por separado (`agro_repository.dart:4373-4379`) del libro de cuentas (`4383-4386`).

### PAG-08 · Revertir una compra anula sus pagos sin borrarlos
- **Dado** una compra con pagos al proveedor, **cuando** el titular la revierte (motivo y PIN, RF-13), **entonces**:
  - cada pago no revertido recibe `reversed_at` y la fila se conserva;
  - el pago queda referenciado en `reversal_audit_effects`;
  - la compra queda `REVERSED`;
  - el total pagado deja de contarlo.
- Los pagos de **cuenta** de las personas no se revierten: lo imputado a un cargo revertido queda a favor (CTA-05).
- La aplicación no registra una devolución del proveedor (pregunta Q-08).
- **Código:** `agro_repository.dart:2699-2718`; `app_database.dart:388-391` (tabla de efectos que admite `provider_payments`).
- **Reglas repo:** RN-45, RN-46 y RN-48 (repo).

## 3. Cuentas entre personas (CTA)

Contexto común: modalidad compartida salvo que se diga otra cosa; personas no ADMIN; importes en centavos de Bs. Los términos *P* (deuda pendiente), *F* (a favor, no aplicado a deuda), *N* (saldo neto), *u* (sin imputar), *L* (liberado por reversión) y *X* (compensaciones) son los de `D04_E15` §2.1.

### CTA-01 · El importe de un pago o adelanto es positivo
- **Dado** una persona, **cuando** se registra un pago o adelanto con importe ≤ 0, **entonces** se rechaza con «El importe debe ser mayor a cero.» sin escribir.
- **Código:** `agro_repository.dart:2325-2326`.
- **Regla repo:** RN-36 (repo).

### CTA-02 · Signo de los asientos y saldo neto
- Un cargo es positivo; un pago, adelanto o crédito, negativo.
- **Dado** los asientos de una persona, **entonces** *N* = Σ de sus importes con signo = *P* − *F* (invariante I-2), y Σ por campaña de origen de la deuda = *P* (I-1).
- **Código:** `agro_repository.dart:2336`; `lib/domain/account_ledger.dart:91-111, 235-238`.
- **Regla repo:** RN-37 (repo).

### CTA-03 · Imputación a la deuda más antigua, de cualquier campaña
- **Dado** cargos pendientes en varias campañas, **cuando** se registra un pago, **entonces** se imputa a los cargos con deuda pendiente (importe − revertido − ya imputado):
  - por día local del cargo y, dentro del día, por `id`;
  - sin filtrar por campaña, hasta agotar el importe.
- La campaña del pago es sólo su campaña de registro y puede ser nula.
- El mensaje de éxito dice lo imputado por campaña de origen.
- **Código:** `agro_repository.dart:2341-2361, 2386-2404`.
- **Decisión:** D-04 (autor, 2026-10-27); orden por día y luego `id` según F04 §2.3 (C-08).
- **Regla repo:** RN-38 (repo).

### CTA-04 · Un cargo revertido no recibe imputaciones nuevas
- **Dado** un cargo revertido, **cuando** se registra un pago nuevo, **entonces** no se le imputa nada y el pago va al siguiente cargo con deuda o queda a favor.
- **Código:** `agro_repository.dart:2343-2351`.
- **Criterio:** Q-5 (coordinador; revisable por el autor).
- **Regla repo:** RN-38 (repo), «Cargos revertidos».

### CTA-05 · Las imputaciones guardadas no se recalculan
- **Dado** imputaciones guardadas, **cuando** se registra otro pago, se revierte un cargo o se lee cualquier vista, **entonces** ninguna fila existente de `payment_allocations` cambia ni se borra (I-8).
- Las imputaciones nuevas sólo las crea el pago que se registra.
- Lo imputado a un cargo que después se revirtió queda «liberado por reversión», a favor y sin campaña, y no se reimputa (criterio Q-1).
- **Código:** `agro_repository.dart:2391-2395` (única escritura de `payment_allocations` en `lib/`); `account_ledger.dart:107-109`.
- **Regla repo:** RN-38 (repo).

### CTA-06 · Los asientos se corrigen compensando, no editando (inmutabilidad a nivel de aplicación)
- **Dado** un cargo, **cuando** se revierte la aplicación o la compra que lo originó, **entonces** se inserta un `CREDIT_ADJUSTMENT` con el importe negado y `reversal_of_id` apuntando al cargo; el cargo original y sus imputaciones quedan intactos.
- **Alcance de la garantía:** es sólo de la aplicación. En `5b5b318`, ningún código de `lib/` emite `UPDATE` ni `DELETE` sobre `account_transactions` o `payment_allocations` (búsqueda en `lib/`; la única escritura sobre esas tablas es `insert`).
- **No hay** trigger de base de datos que lo impida. Sí lo hay en `reversal_audit` y `reversal_audit_effects` (`app_database.dart:394-401`), `owner_bindings`, `sync_outbox`, `declared_needs` y `lot_data_corrections`.
- **No existe** la reversión de un pago o adelanto de cuenta (H-10 de `D04_E15`). La clase «compensación de un crédito» está prevista y no se trata como deuda.
- **Fuera de esta regla:** restaurar un respaldo reemplaza la base completa; no es una edición de filas.
- La inmutabilidad en base de datos queda como **pregunta abierta** (Q-03), no como requisito.
- **Código:** `agro_repository.dart:2507-2528` (aplicación) y `2682-2698` (compra).
- **Regla repo:** RN-46 (repo).

### CTA-07 · El saldo continúa entre campañas
- **Dado** deuda de una campaña, **cuando** se cierra la campaña o se activa otra, **entonces** el saldo neto de la persona no cambia y la deuda sigue atribuida a su campaña de origen.
- **Cuando** se consulta el estado cronológico de una campaña K, **entonces** incluye todos los asientos con día local dentro del período de K, de cualquier campaña o sin campaña:
  - empieza en «Saldo al inicio del período» (Σ de los asientos con día anterior al inicio);
  - termina en «Saldo al cierre del período» si el período ya terminó, o en «Saldo a hoy».
- `personCampaignBalance` conserva el cálculo anterior por campaña sólo para su caracterización (`agro_repository.dart:4194-4218`); ninguna pantalla lo usa.
- **Código:** `agro_repository.dart:4185-4192` (`accountStatement`).
- **Criterio:** Q-4 (coordinador; revisable).
- **Reglas repo:** RN-15 y RN-42 (repo).

### CTA-08 · Adelantos
- **Dado** una persona con deuda, **cuando** se registra un adelanto o un pago, **entonces** los dos se imputan igual. Sólo cambia `type`/`reference_type` (`ADVANCE` o `PAYMENT`).
- **Cuando** no hay deuda, **entonces** el importe queda sin imputar, a favor y sin campaña.
- Un adelanto anterior a los cargos **no** se imputa a cargos posteriores (criterio Q-1). La persona puede ver deuda pendiente por origen y crédito a favor a la vez, con *N* correcto.
- Desde el 2026-10-30 Cuentas ofrece un único «Registrar pago», que guarda `PAYMENT` y dice «Si no hay deuda, el pago queda a favor (como un adelanto).». Los `ADVANCE` guardados se siguen leyendo como «Adelanto».
- **Código:** `agro_repository.dart:2331-2339`; `lib/domain/account_texts.dart:232`; `settlements_screen.dart:124-128`.
- **Regla repo:** RN-39 (repo).

### CTA-09 · Crédito a favor
- **Dado** una persona, **cuando** el pago supera su deuda pendiente, **entonces** se acepta (los pagos de cuenta no tienen tope, H-04 de `docs/16_VALIDATIONS.md`).
- El sobrante queda sin imputar y se informa como «A favor (no aplicado a deuda)», sin campaña, con *F* = *u* + *L* − *X*.
- En Inicio, «Familias/Terceros por cobrar» = Σ max(0, *N*) por persona, y lo que queda a favor se informa aparte («A favor de …»).
- **Código:** `agro_repository.dart:2405-2411`; `account_ledger.dart:235`; `agro_repository.dart:4380-4386`.
- **Regla repo:** RN-40 (repo).

### CTA-10 · El consumo propio del titular no es cuenta por cobrar
- **Dado** un asiento de quien era titular en su día local (o del titular vigente), **entonces** es «propio»: no entra en Cuentas, en «por cobrar», en «Pagos recibidos» ni en el resumen de campaña. Se muestra en «Consumo y costos propios».
- **Cuando** se registra un pago, **entonces** sólo se imputa a cargos de su misma clase (propio o por cobrar).
- **Código:** `agro_repository.dart:2362-2383`; `account_ledger.dart:152-185`.
- **Decisión:** E-15 (autor, 2026-10-27).
- **Criterios:** Q-2 y Q-3 (coordinador; revisables).

### CTA-11 · Quién figura en la liquidación
- **Dado** el modo propio, **cuando** se registra un pago de cuenta a otra persona que no es el titular, **entonces** se rechaza sin cambios (#26; criterio Q-2).
- Las personas `ADMIN` no aparecen en la lista de Cuentas ni en el resumen de campaña.
- **Código:** `agro_repository.dart:2328-2330`.
- **Regla repo:** RN-41 (repo).

## 4. Trazabilidad

### 4.1 Tabla

«Doc.» = ID del documento v1.22.1. **«—»** = sin requisito equivalente en el documento; la regla queda como propuesta para revisión del autor. «Rel.» = el documento contiene un requisito **relacionado pero no equivalente**: su texto (§4.2) cubre una parte del contexto y no la regla. Las pruebas se citan por archivo y nombre.

| Regla | Regla repo (`docs/15`) | Doc. | Código (`5b5b318`) | Prueba(s) | Evidencia y procedencia | Estado de la evidencia |
|---|---|---|---|---|---|---|
| PAG-01 | RN-16 (repo) | — | `agro_repository.dart:1247-1248`; `app_database.dart:576-578` | **Ninguna** de repositorio para el pago al proveedor ≤ 0 | — | Sin prueba específica |
| PAG-02 | RN-16 (repo) | — | `agro_repository.dart:1299-1309` | **Ninguna** que provoque «supera el saldo». Pagos parciales y totales aceptados: `repository_test` «asignación familiar no crea deuda; uso y pago parcial sí», `f04_bug_02_reverse_purchase_after_transfer_test` «multiproducto con un tercero y pago…» | Diálogo con «máximo 90,00»: EMULADOR, `F10_X01_PAGO_DATOS_EMULADOR_0F1E15F.md` E8 (sólo interfaz) | Rechazo sin prueba; prueba HOST en curso (§6.1) |
| PAG-03 | RN-16 (repo) | — | `agro_repository.dart:1282-1289`; `purchases_screen.dart:246` | **Ninguna** que pague una compra revertida | Menú sin «Registrar pago» en una compra revertida: no consta en evidencias | Sin prueba; prueba HOST en curso (§6.1) |
| PAG-04 | RN-16 (repo) | — | `agro_repository.dart:1290-1298` | `f10_x01_pago_datos_test`: «el medio indicado se guarda tal cual, también «Sin indicar»», «fecha de pago futura: no se escribe ni la compra ni el pago», «fecha de pago anterior a la compra (anticipo)…», «pago posterior: no futuro; el medio y la fecha se guardan» | EMULADOR `F10_X01_PAGO_DATOS_EMULADOR_0F1E15F.md` E5–E9, E23–E26 (`0f1e15f`) | HOST + EMULADOR |
| PAG-05 | RN-16 (repo) | — | `agro_repository.dart:1058-1072, 1250-1255` | `f10_x01_pagador_titular_test`: «candidatos a pagador: sólo el titular, aunque haya un ADMIN», «pago posterior por otra persona (familiar o ADMIN): se rechaza sin cambios», «los pagos históricos de un ADMIN se conservan tal cual»; `f04_repository_guards_test` «pago al proveedor registrado por otra persona» | DEVICE POCO `F10_X01_CORRECCIONES_22E4E45.md` §3, filas 4 y 22 (`22e4e45`, no la versión final); EMULADOR `F10_X01_PAGO_DATOS_EMULADOR_0F1E15F.md` E6, E8, E25 | HOST + EMULADOR; DEVICE sobre una versión anterior |
| PAG-06 | — | Rel. RNF-02 | `agro_repository.dart:1016-1050` | `f10_x01_pagador_titular_test` «compra pagada al confirmar: compra y pago en la misma escritura, a nombre del titular y con la fecha de la compra»; `f10_x01_pago_datos_test` «fecha de pago futura: no se escribe ni la compra ni el pago» | DEVICE POCO `F10_X01_CORRECCIONES_22E4E45.md` fila 4 (`22e4e45`); EMULADOR `F10_X01_PAGO_DATOS_EMULADOR_0F1E15F.md` E6 | HOST + EMULADOR; DEVICE sobre una versión anterior |
| PAG-07 | — (el issue #45 lo pide; `docs/15` no lo numera) | — | `agro_repository.dart:1310-1316, 4373-4386` | Indirectas: `f04_historical_admin_owner_test` «compartido: compra, aplica en su chaco, transfiere y paga; reglas de cobro intactas» (cuentas iguales tras el pago); `reports_test` «refleja pagos de proveedor y de cuenta» | — | Indirecta; falta la prueba directa (§6.1) |
| PAG-08 | RN-45, RN-46, RN-48 (repo) | Rel. RF-13, CU-17, RN-05 | `agro_repository.dart:2699-2718` | `f04_bug_02_reverse_purchase_after_transfer_test` «multiproducto con un tercero y pago: …la compra se revierte una sola vez»; `ux_c1_detalle_compra_test` «una compra revertida muestra el estado, la auditoría y los pagos revertidos» | EMULADOR `F10_UX_C1_EMULADOR_2026-10-30.md` («Pagado y no revertido: 0,00 Bs» en F-1040) | HOST + EMULADOR |
| CTA-01 | RN-36 (repo) | — | `agro_repository.dart:2325-2326` | **Ninguna** de repositorio para un importe ≤ 0. `payment_dialog_test` «UIBUG-065…» sólo cubre el texto del diálogo | — | Sin prueba específica |
| CTA-02 | RN-37 (repo) | — | `agro_repository.dart:2336`; `account_ledger.dart:91-111, 235-238` | `d04_imputacion_ledger_test`: `invariants()` (I-1 a I-7) en cada ejemplo D04 y M | `F10_BLOQUE2_D04_IMPUTACION.md` (HOST) | HOST |
| CTA-03 | RN-38 (repo) | — | `agro_repository.dart:2341-2361, 2386-2404` | `v4_repository_test` «saldo inicial cruza campañas y el pago se imputa a deuda antigua»; `d04_imputacion_ledger_test` «pago global de 50…», «D04-02 · pago registrado en la campaña nueva cancela deuda antigua», «D04-03 · un pago repartido entre dos campañas», «M-3 · cargos del mismo día: día y luego id» | HOST `F10_BLOQUE2_D04_IMPUTACION.md` (con discriminación sobre `ed9c55c`); EMULADOR `F10_BLOQUE2_EMULADOR_2026-10-28.md` (pago de 10 Bs «Imputado: Verano Demo 10,00 Bs») | HOST + EMULADOR |
| CTA-04 | RN-38 (repo) | — | `agro_repository.dart:2343-2351` | `d04_imputacion_ledger_test` «pago nuevo: no se imputa al cargo revertido (criterio Q-5)», «M-2r · variante revertida…», «07h seguido de un pago nuevo…»; `d04_imputacion_base_test` «D04-07 · el pago nuevo no se imputa al cargo revertido…» | HOST `F10_BLOQUE2_D04_IMPUTACION.md` | HOST |
| CTA-05 | RN-38 (repo) | — | `agro_repository.dart:2391-2395`; `account_ledger.dart:107-109` | `d04_imputacion_ledger_test` «D04-06 · reversión de un cargo con pago imputado» (I-8), «D04-08 · …», «D04-09b · pago histórico sin imputaciones: no se fabrica ninguna», «07h seguido de un pago nuevo…»; `d04_imputacion_real_ops_test` «M-4 y D04-06 reales…» | HOST `F10_BLOQUE2_D04_IMPUTACION.md` | HOST |
| CTA-06 | RN-46 (repo) | Rel. RF-13, RU-14, RN-05 | `agro_repository.dart:2507-2528, 2682-2698`; sin triggers en `app_database.dart:608-617` | `repository_test` «reversión de aplicación restaura inventario y revierte el cargo»; `f04_bug_02_reverse_purchase_after_transfer_test` (crédito con `reversal_of_id`); `d04_imputacion_ledger_test` «§2.1 · una compensación futura de un crédito no es deuda» | HOST | HOST (nivel de aplicación); en base de datos: pregunta abierta Q-03 |
| CTA-07 | RN-15, RN-42 (repo) | Rel. RN-06 | `agro_repository.dart:4185-4192` | `v5_domain_test` «catálogo, stock y deuda permanecen al cambiar campaña»; `d04_imputacion_ledger_test` «pago global de 50…» (cronológico de Invierno: inicio 81, a hoy 71), «campaña ACTIVA con fin pasado…», «asiento en un hueco entre campañas…»; `d04_imputacion_base_test` «M-8 · estado de cuenta filtrado por Invierno…» | HOST `F10_BLOQUE2_D04_IMPUTACION.md` | HOST |
| CTA-08 | RN-39 (repo) | — | `agro_repository.dart:2331-2339`; `account_texts.dart:232` | `ux_c1_correcciones_test` «mismas imputaciones, saldos y totales; sólo cambia el tipo», «registrar desde Cuentas escribe un PAYMENT…»; `d04_imputacion_ledger_test` «D04-05 · anticipo seguido de cargos (criterio Q-1: no se imputa)», «M-5 · adelanto sin cargos»; `repository_test` «tercero genera cargo por allocation y adelanto lo compensa» | HOST `F10_UX_C1_CORRECCIONES_2026-10-30.md`; EMULADOR `F10_UX_C1_EMULADOR_2026-10-30.md` («Pago único», «Lectura de adelantos históricos») | HOST + EMULADOR |
| CTA-09 | RN-40 (repo) | — | `agro_repository.dart:2405-2411, 4380-4386`; `account_ledger.dart:235` | `d04_imputacion_ledger_test` «D04-04 · exceso de pago», «M-5 · adelanto sin cargos»; `d04_imputacion_base_test` «D04-04 · Familias por cobrar 0 (hoy −19)» y la pantalla de Inicio «D04-04 · Inicio: …» | HOST `F10_BLOQUE2_D04_IMPUTACION.md`; EMULADOR `F10_UX_C1_EMULADOR_2026-10-30.md` («Sobrante a favor») | HOST + EMULADOR |
| CTA-10 | — (E-15; `docs/15` lo anota bajo RN-41) | — | `agro_repository.dart:2362-2383`; `account_ledger.dart:152-185` | `e15_consumo_propio_ledger_test` «E15-01 …», «E15-04 · pago propio en Invierno: no es «Pagos recibidos»…», «A1 · pago de P1 tras el cambio…», «A1 inverso · un pago propio no cancela un cargo por cobrar»; `e15_consumo_propio_base_test` (E15-01, E15-04, A1) | HOST `F10_BLOQUE2_E15_CONSUMO_PROPIO.md`; EMULADOR `F10_BLOQUE2_EMULADOR_2026-10-28.md` (tarjeta «Consumo y costos propios», el titular fuera de la lista) | HOST + EMULADOR |
| CTA-11 | RN-41 (repo) | — | `agro_repository.dart:2328-2330` | `f04_repository_guards_test` «chaco, plan y pago de cuenta de otra persona»; `personal_mode_flows_test` «liquidación: pagos y adelantos sólo del titular»; `d04_imputacion_ledger_test` «el ADMIN no entra en la lista ni en el resumen (D-R6)» | HOST | HOST |

### 4.2 Textos del documento citados

Requisitos del documento que la tabla marca como «Rel.». Ninguno trata los pagos al proveedor ni las cuentas entre personas.

- **RNF-02** (Must): «Las operaciones locales confirmadas deberán permanecer completas ante pérdida temporal de conectividad, cierre y reapertura de la aplicación, evitando efectos parciales ante una escritura fallida.» Cubre la atomicidad de PAG-06, no la regla del pago.
- **RF-13** (Must): «Permitir corregir o revertir una operación cuando el actor y ámbito lo autoricen, preservando la operación original, responsable, fecha, motivo y efecto correctivo. Una misma reversión no deberá producir dos restituciones.» **CU-17** limita esas operaciones a «compras, aplicaciones y transferencias»; no menciona pagos ni asientos de cuenta.
- **RN-05** (doc.), «Reversión trazable»: «Toda reversión o corrección deberá identificar la operación original, el responsable y el motivo. La corrección no borrará la evidencia original ni podrá producir dos veces el mismo efecto correctivo.»
- **RU-14:** «Corregir operaciones autorizadas preservando la operación original, la explicación del cambio y el efecto correctivo correspondiente.»
- **RN-06** (doc.), «Cierre de campaña e histórico»: «Una campaña finalizada conservará su historial. […] La consulta del histórico no modifica el estado de la campaña ni sus operaciones.» No habla de saldos de cuentas.
- **RF-07** (Must) cubre el registro de la compra («…produciendo entradas de inventario trazables para las líneas confirmadas»), no su pago. La ficha CU-06 tampoco menciona el pago.

El documento sí **describe** la construcción, pero esa descripción no es un requisito con ID:
- **1.4.2, OE3:** «Implementar los módulos de inventario, compras, cuentas por pagar, …».
- **3.13.2:** «se incorporarán […] la imputación de pagos a la deuda más antigua y el consumo propio del titular separado de las cuentas por cobrar», y «P-03 a P-05 […] orientarán las pruebas de saldos, […] junto con la compra con pago en una sola transacción, la imputación de pagos entre campañas…».
- **3.14.2.1:** «Pasar a la propia se rechaza mientras existan existencias, planes abiertos o saldos de terceros» y «Desde el 28 de octubre de 2026 el consumo del titular se presenta como «consumo y costos propios», separado de las cuentas por cobrar.».
- **3.14.2.3:** «El pago al proveedor, registrado por el titular vigente, se guarda en la misma transacción, de modo que un fallo no deja una compra sin pago ni la duplica al reintentar.»
- **3.14.2.5:** «Las cuentas entre personas registran cargos, pagos y adelantos, y cada pago se imputa a la deuda más antigua sin recalcular imputaciones históricas.»
- **Tabla 3.57:**
  - «Compras, pagos, inventario y aplicaciones (F04)»: pendiente «Repetición en dispositivo con la versión final; estudio de usabilidad.»;
  - «Transferencias, correcciones y operaciones tardías (F04)», que incluye «cuentas con imputación a la deuda más antigua»: pendiente «Transferencia en dispositivo en modalidad compartida; retorno desde una operación tardía.».

### 4.3 Propuesta de requisitos para el autor

Sin número, porque asignarlo corresponde al autor en la próxima revisión del documento:
- **RF propuesto «Pago al proveedor»:** PAG-01 a PAG-08.
- **RF propuesto «Cuentas entre personas»:** CTA-01 a CTA-11.
- **DAT propuesto «Pagos, asientos e imputaciones»:** `provider_payments`, `account_transactions` y `payment_allocations`, con la regla de compensación de CTA-06.

Antes conviene resolver Q-01 y Q-02 (§6.3).

## 5. Numeración del repositorio frente a la del documento

1. **Mismo prefijo, otro significado.** `docs/15_BUSINESS_RULES.md` numera RN-01…RN-52 (más RN-PLAN-01 y RN-CAMPAIGN-02) a partir del código. El documento v1.22.1 numera RN-01…RN-32 con otro contenido. Ejemplos:

   | Número | `docs/15` (repo) | Documento v1.22.1 |
   |---|---|---|
   | RN-03 | «Los catálogos se archivan, nunca se borran» | «Prevención de saldo negativo» |
   | RN-05 | «No se pueden repetir productos dentro de una compra» | «Reversión trazable» |
   | RN-15 | «Cerrar campaña NO afecta al inventario ni a la deuda» | «Asignación temporal de campaña por fecha efectiva» |
   | RN-16 | «El pago al proveedor no puede superar el saldo de la compra» | «No solapamiento y determinación inequívoca de campaña» |

   RN-33…RN-52 (repo), entre ellas todo el grupo G de cuentas (RN-36…RN-42) y RN-45/RN-46 de reversión, **no tienen número homólogo** en el documento.
2. **Sin requisito equivalente.** Ninguna regla de pagos al proveedor (RN-16 y RN-45, repo) ni de cuentas (RN-36…RN-42, repo) tiene un RU, RN, CU, RF, RNF, INT o DAT equivalente en el documento. Se listan como propuesta (§4.3).
3. **Usos mezclados dentro del repositorio** (no se corrigen aquí):
   - `docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md:6` cita «RN-15, RN-16» en el sentido del documento (campañas por fecha y sin solapamiento).
   - El comentario de `test/v5_domain_test.dart` «RN-15/RN-16: … antes empezaba en junio y solapaba» también usa el sentido del documento. En `docs/15`, RN-16 es el tope del pago al proveedor.
   - En `docs/15`, el bloque de RN-35 traza «RN-35, RN-10, RN-27, CU-08, RF-11»: mezcla RN del repositorio con CU/RF del documento.
   - `docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md:192, 195, 223` cita «RN-39» junto a la guarda de paso a modo propio. Ese uso no coincide con RN-39 de `docs/15` («Adelanto y pago comparten mecánica») y RN-39 no existe en v1.22.1. No se interpreta aquí.
4. **Referencias de los issues.** Los cuerpos de #45 y #49 dicen «Relación con Capítulo III: 3.5.3», pero en v1.22.1 la sección 3.5 sólo tiene 3.5.1 y 3.5.2. «Requirement refs» sigue en `TRACEABILITY_PENDING_F01`.
5. **`docs/31_TRACEABILITY_MATRIX.md` desactualizado** (no se corrige aquí). Dice que RN-40 (repo) no tiene prueba; hoy la cubren «D04-04 · exceso de pago» y «M-5 · adelanto sin cargos». Sigue siendo cierto que RN-16 (repo) no tiene prueba del tope.

## 6. Brechas

### 6.1 Pruebas que faltan

| Regla | Prueba que falta | Situación |
|---|---|---|
| PAG-02 | Un pago por encima del saldo se rechaza sin cambios; el pago justo hasta *T* se acepta | **En curso en otra sesión** (pruebas HOST, rama local `test/oe3-host-cierre`, sin publicar a la fecha de este documento). No se cuenta como evidencia hasta que exista su commit y su salida |
| PAG-03 | Pagar una compra revertida se rechaza sin cambios | **En curso** en la misma rama; mismo criterio |
| PAG-01 | Pago al proveedor de 0 y negativo: rechazo sin cambios | No consta en curso; se propone |
| PAG-07 | `account_transactions` y `payment_allocations` idénticas antes y después de `addProviderPayment` y de `confirmPurchase(paidInFull:)` | No consta en curso; se propone |
| CTA-01 | Pago o adelanto de cuenta de 0 y negativo: rechazo sin cambios | No consta en curso; se propone |
| CTA-06 | Ninguna operación de `AgroRepository` modifica o borra filas existentes de `account_transactions` o `payment_allocations` (comparación de las filas antes y después de un recorrido completo) | No consta en curso; se propone |

### 6.2 Verificación en dispositivo pendiente

- **Ninguna regla CTA** tiene recorrido en un teléfono físico. Sus recorridos son de EMULADOR (2026-10-28 y 2026-10-30).
- **PAG-05 y PAG-06** se recorrieron en el POCO el 2026-10-26 sobre `22e4e45`, no sobre la versión final. Desde entonces cambiaron el medio y la fecha del pago (PR #149) y el detalle de la compra (#162).
- Según la tabla 3.57 y el comentario de #49, falta la repetición en dispositivo con la versión final, también en **modalidad compartida**, que es donde existen las cuentas por cobrar.
- Este documento no aporta evidencia DEVICE nueva.

### 6.3 Preguntas abiertas para el autor

- **Q-01 · Alcance.** El documento dice cosas que conviene conciliar:
  - 1.5.2 excluye «contabilidad general, tesorería, banca…»;
  - la nota tras la tabla 3.23 dice que «El registro económico explica compras de agroquímicos y no introduce contabilidad general, caja, banca o pagos familiares.»;
  - 3.13.1 deja fuera «la contabilidad y los pagos heredados sin requisito vigente»;
  - en cambio, OE3 incluye «cuentas por pagar» y 3.14.2.5 describe cuentas entre personas con pagos y adelantos, que alcanzan a familiares con cobro por consumo.

  ¿Las cuentas entre personas entran con un requisito propio, o se describen como funcionalidad heredada sin requisito? «Cuentas por pagar» (OE3) parece referirse al proveedor, y las cuentas entre personas son cuentas por cobrar.
- **Q-02 · Requisitos.** ¿Se crean un RF de pago al proveedor, un RF de cuentas y un DAT (§4.3)? ¿Qué reglas PAG/CTA se adoptan tal cual y cuáles se descartan?
- **Q-03 · Inmutabilidad en base de datos.** ¿Se añaden triggers `BEFORE UPDATE/DELETE … RAISE(ABORT)` sobre `account_transactions` y `payment_allocations`, como en `reversal_audit`?
  - `provider_payments` necesita la transición `reversed_at` NULL → fecha, así que su trigger tendría que admitir sólo ese cambio, como el de cierre de `owner_bindings`.
  - Exige migración de esquema y probar la restauración de respaldos anteriores. Hoy no es un requisito.
- **Q-04 · Corregir un pago de cuenta equivocado.** No existe su reversión (H-10). ¿Hace falta, con motivo y PIN como RF-13? La clase «compensación de un crédito» ya está prevista en el libro.
- **Q-05 · Criterios del coordinador.** ¿Confirma el autor Q-1…Q-5 de `D04_E15` §7? En particular:
  - Q-1: un anticipo previo no se imputa a cargos posteriores, así que puede verse una deuda por origen de 300 con un saldo neto de 0;
  - el «hallazgo 4»: ese caso no bloquea el paso a modo propio.
- **Q-06 · Fecha del pago de cuenta.** `registerAccountPayment` no rechaza una fecha futura (`agro_repository.dart:2334`), a diferencia del pago al proveedor (PAG-04). La pantalla siempre usa «ahora». ¿Se iguala la regla?
- **Q-07 · Sin tope en los pagos de cuenta.** ¿Se confirma como regla que un pago de cuenta puede superar la deuda y queda a favor (CTA-09; H-04 de `docs/16_VALIDATIONS.md` lo considera intencional)?
- **Q-08 · Pago de una compra revertida.** Revertir la compra anula sus pagos al proveedor (PAG-08), pero la aplicación no registra una devolución ni un crédito con el proveedor. ¿Es la semántica deseada?

## 7. Verificación de este documento

Comprobaciones hechas el 2026-11-03 sobre `5b5b318`, sin cambiar código:
- Lectura del código citado.
- Búsqueda de `UPDATE`/`DELETE` y de triggers sobre las tablas de cuentas en `lib/` y `test/`.
- Ejecución de los archivos de prueba citados, en tandas de tres (resultado abajo).

```text
# HOST: Windows 11, Flutter 3.47.2, sqflite_common_ffi; worktree limpio en 5b5b318
# 2026-11-03 15:50:13Z – 15:52:10Z; flutter test --timeout 120s <tanda>
repository_test, v4_repository_test, v5_domain_test                                   -> +21: All tests passed!
f10_x01_pago_datos_test, f10_x01_pagador_titular_test, f04_bug_02_reverse_purchase_after_transfer_test -> +23: All tests passed!
d04_imputacion_ledger_test, d04_imputacion_base_test, d04_imputacion_real_ops_test    -> +48: All tests passed!
e15_consumo_propio_ledger_test, e15_consumo_propio_base_test, ux_c1_correcciones_test -> +45: All tests passed!
f04_repository_guards_test, f04_historical_admin_owner_test, reports_test             -> +41: All tests passed!
ux_c1_detalle_compra_test, personal_mode_flows_test, payment_dialog_test              -> +34: All tests passed!
```

- **Resultado:** 212 pruebas, todas en verde.
- **Alcance:** que pasen no prueba las reglas sin prueba específica (§6.1); sólo confirma que las citadas siguen en verde sobre la base.
- **Lo que no se hizo:** no se ejecutó la suite completa, no se midió la cobertura y no hubo recorridos en EMULADOR ni en DEVICE.
