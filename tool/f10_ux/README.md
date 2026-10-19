# DS-UX Mobile — estado inicial de las sesiones de usabilidad F10

Herramienta de evaluación para RNF-07 (protocolo F10 v1.4, §3.3.1; paquete `docs/evaluation/usabilidad/` del repositorio Backend, `09_fixture_y_valores_esperados.md` §1–§2). **No forma parte de la aplicación** (`lib/` no la importa) **ni de la suite** (`flutter test` sin argumentos sólo recorre `test/`). **No simula sesiones ni participantes:** deja el estado inicial de cada instalación de `.f10ux` y, después, lee lo que la sesión guardó.

- Preparada por la sesión C de Claude Code el 2026-10-18 (America/La_Paz), por el encargo de Roderich Rendón transmitido por la sesión A. Ninguna sesión de usabilidad ejecutada.
- Trazabilidad: RNF-07 (RU-13), INT-01, INT-08; MOB #37 (UX-01); GATE-F10 (Backend #49) Pending.

## Archivos

| Archivo | Qué hace |
|---|---|
| `dsux_fixture.dart` | Composición DS-UX-1, semilla 20261018, validaciones, siembra (`seedDsux`) y oráculo (`dsuxOracle`, `expectedBalanceBase`) |
| `seed_dsux_mobile.dart` | Siembra sobre la base extraída de `.f10ux`; imprime `DSUX_RESULT {…}` |
| `oracle_dsux_mobile.dart` | Sólo lectura sobre una copia de la base; imprime `DSUX_ORACLE {…}` |
| `../../test/f10_ux_dsux_fixture_test.dart` | Prueba de la composición, los vínculos, las dos modalidades, T1–T2 nominales, T4, T6, el oráculo y las negativas |

## Composición (DS-UX-1)

Todas las fechas son días civiles de **America/La_Paz** relativos al día de sesión `S` (`F10_UX_SESSION_DATE`).

| Elemento | Valor | Cómo se escribe |
|---|---|---|
| Campaña local | «Verano Demo», activa, del `S − 14` al `S + 30` (o al fin de la central, si es anterior) | `AgroRepository.addCampaign` |
| Chacos | «Norte» (1 ha) y «Sur» (0,8 ha, distractor), del titular | `addFarm` |
| Persona adicional | **Sólo en COMPARTIDA:** «Familiar Demo» (familiar), para que la elección de persona y las asignaciones sean reales | `addPerson` |
| Proveedor | «Proveedor Demo» | `addSupplier` |
| Productos | «Glifosato Demo» y «Bellator», en L (base mL) | `addProduct` |
| Existencias iniciales | Glifosato Demo **5 L** (45,00 Bs/L) y Bellator **1 L** (180,00 Bs/L), una compra confirmada cada uno el `S − 10` a las 09:00, asignada al titular, facturas `DSUX-INI-1` y `DSUX-INI-2` | `confirmPurchase` (fecha efectiva, campaña activa, titular, asignación) |
| Vínculos | Campaña y los dos productos con sus homónimos centrales, **explícitos** | `CentralBindingStore.bindCampaign` / `bindProduct`, el mismo código que la pantalla «Vincular con el sindicato» (contención D-F04-C2 incluida) |
| Sync | Ninguna intención nueva (se comprueba); ninguna necesidad declarada | — |

La composición es fija; la semilla identifica la versión del dataset y no introduce elecciones aleatorias. «Belator», si Central lo publica, no se vincula: es el producto de W3 en la Web.

## Requisitos previos

1. **Copia recién activada.** `.f10ux` reinstalada y activada por el facilitador con una cuenta sintética nueva, eligiendo la **modalidad del participante** (propia o compartida, según el diseño de la muestra). El generador exige: sólo el titular como persona, ninguna campaña, chaco, producto, proveedor, compra, aplicación, plan, transferencia, necesidad ni vínculo.
2. **Referencias de Central** del tenant de esa cuenta: el cuerpo literal de `GET /api/v1/sync/v1/references`, guardado en un archivo. Lo escribe en `F10_UX_REFERENCES` el generador Central/Web de la sesión B (destino «movil»), que antes comprueba que la campaña y los productos del JSON son los del **mismo tenant** que las cuentas de los participantes y lo declara en su salida (`same_tenant_as_accounts`); este generador no puede comprobarlo, porque el JSON no lleva el tenant. Central debe publicar:
   - «Verano Demo» ABIERTA y con `accepts_contributions`, con un período que **contenga** del `S − 14` al `S + 30`, o que empiece a más tardar el `S − 14` y no termine antes del día `S`;
   - «Glifosato Demo» y «Bellator» activos, en L.
   Cada nombre debe aparecer exactamente una vez.
3. **PC en America/La_Paz (UTC−4)**, como el teléfono; si no, los días civiles no coincidirían y la siembra se niega.
4. **Día de sesión** hoy o en los próximos 10 días: la compra inicial (`S − 10`) no puede ser futura.

## Uso

Con la app detenida (`am force-stop`) y la base extraída de la copia (`run-as … cat`):

```bash
F10_UX_DB=/ruta/absoluta/agroquimicos_v2.db \
F10_UX_SESSION_DATE=2026-10-20 \
F10_UX_MODALIDAD=COMPARTIDA \
F10_UX_REFERENCES=/ruta/absoluta/references.json \
  flutter test tool/f10_ux/seed_dsux_mobile.dart
```

`F10_UX_MODALIDAD` acepta `PROPIA` (o `INDIVIDUAL`, el valor de la hoja de registro y de `participantes.csv`) y `COMPARTIDA`, y **debe coincidir con la modalidad elegida al activar**: el generador no la cambia. La base se devuelve al teléfono con el mismo procedimiento que DS-V (`push` + `run-as cp`) y su SHA-256 se compara en el PC y en el teléfono antes de abrir la app.

**Todas las comprobaciones se hacen antes de escribir.** Si una falla, el generador lanza `DsuxRefused` con el motivo y la base queda como estaba. Si fallara una escritura a mitad (no previsto), la copia se reinstala y se activa de nuevo, como prevé el protocolo para cada participante.

`DSUX_RESULT` registra la versión, la semilla, el día de sesión, la modalidad, el período local y el central, el estado de los tres vínculos (`VALID`), los saldos (5 000 y 1 000 mL), los conteos y la integridad. Se copia a la hoja de la sesión.

## Oráculo de T3 (y de T4)

**Nominal**, tras T1 (+2 L de Glifosato Demo, +500 mL de Bellator) y T2 (−1 L, −200 mL en «Norte»): **Glifosato Demo 6 L y Bellator 1,3 L**.

**Condicionado a lo guardado** (`09_…` §2): saldo esperado = inicial + compras **guardadas** − aplicaciones **guardadas**.

| T1 guardó (Bellator) | T2 guardó (Bellator) | Saldo esperado de Bellator |
|---|---|---|
| 500 mL | 200 mL | 1 300 mL |
| nada | 200 mL | 800 mL |
| 500 mL | nada | 1 500 mL |
| nada | nada | 1 000 mL |
| otro valor | — | el que resulte de lo guardado |

Durante la sesión, el facilitador lee el saldo en Inventario antes de entregar T3 (guion §6). **Después** de la sesión, con la app detenida y la base extraída:

```bash
F10_UX_DB=/ruta/absoluta/agroquimicos_v2.db flutter test tool/f10_ux/oracle_dsux_mobile.dart
```

`DSUX_ORACLE` da, por producto, la existencia inicial, lo comprado y aplicado **guardado** después de la siembra, el saldo esperado, el saldo de los movimientos, si coinciden, **el saldo por persona** (en compartida) y cada operación con su fecha, estado, chaco y persona; y las necesidades declaradas (T4) y el estado de la cola de Sync (T5). Lee una **copia** en un directorio temporal: el archivo indicado no se abre ni se modifica. **No corrige nada**: lo que el participante guardó es el dato; su error ya consta en su tarea.

## Lo que no hace

- No opera el teléfono ni activa cuentas (lo hace la sesión A, que también ejecuta el generador Central de B que escribe las referencias).
- No toca Central ni la Web (generador de la sesión B).
- No cambia esquema, reglas ni pantallas de la app.
- No produce resultados de usabilidad ni cuenta como participante.
