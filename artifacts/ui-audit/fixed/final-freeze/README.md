# Evidencia de la congelación de la baseline — 2026-09-06

Capturas de la regresión final sobre el Pixel 8, tomadas al cerrar la baseline
`v1.0.0-base-stable`. Informe: [`docs/46_BASELINE_FINAL_FREEZE.md`](../../../../docs/46_BASELINE_FINAL_FREEZE.md).

**Entorno** — AVD `Pixel_8` (`emulator-5554`, `sdk_gphone16k_x86_64`) · Android **16 (API 36)**
· 1080 × 2400 px · 420 dpi (densidad 2,625) · fuente 1.0 salvo donde se indica · vertical
salvo donde se indica. Dataset determinista de
[`36_UI_AUDIT_DATASET`](../../../../docs/36_UI_AUDIT_DATASET.md), regenerado en esquema v6.

Las 119 capturas originales de la auditoría (`artifacts/ui-audit/UI-*/`) y las de las fases
anteriores (`artifacts/ui-audit/fixed/<UIBUG>/`, `fixed/regression/`) **siguen intactas**:
ninguna se sustituyó.

## Recorrido de las 17 rutas

| Archivo | Ruta |
|---|---|
| `UI-01-inicio.png`, `UI-01-inicio-final.png` | UI-01 `/` — inventario en tarjetas; última fila sobre el FAB |
| `UI-02-operaciones.png` | UI-02 `/operaciones` |
| `UI-03-catalogos-personas.png`, `UI-03-catalogos-campanas.png` | UI-03 `/catalogos` |
| `UI-04-planificacion.png` | UI-04 `/planificacion` |
| `UI-05-plan-form.png`, `UI-05-plan-producto-agregado.png` | UI-05 `/planificacion/nueva` |
| `UI-06-compras.png`, `UI-06-factura-antes-del-respaldo.png`, `UI-06-pago-proveedor.png`, `UI-06-pago-registrado.png` | UI-06 `/compras` |
| `UI-07-compra-form-inicial.png` | UI-07 `/compras/nueva` |
| `UI-08-aplicaciones.png`, `UI-08-reversion-confirmacion.png` | UI-08 `/aplicaciones` |
| `UI-09-aplicacion-desde-plan.png` | UI-09 `/aplicaciones/nueva` |
| `UI-10-liquidacion.png` | UI-10 `/liquidacion` |
| `UI-11-inventario.png` | UI-11 `/inventario` |
| `UI-12-inventario-detalle.png` | UI-12 `/inventario/:id` |
| `UI-13-personas.png` | UI-13 `/personas` |
| `UI-14-persona-detalle.png` | UI-14 `/personas/:id` |
| `UI-15-bitacora.png` | UI-15 `/chacos/:id` |
| `UI-16-transferencias.png` | UI-16 `/transferencias` |
| `UI-17-transferencia-con-origen.png` | UI-17 `/transferencias/nueva` |

## Por UIBUG

| Archivo | UIBUG |
|---|---|
| `UI-01-inicio.png`, `A11Y-130-inicio-inventario.png` | **023** identidad del producto sin scroll horizontal · **067** cinta de campaña activa |
| `UIBUG-031-validacion-visible.png` | **031** validación visible en catálogos |
| `UIBUG-032-plan-validacion-1.png`, `-2.png` | **032** mensajes de validación del plan, distintos por condición |
| `UIBUG-036-sin-resultados-con-teclado.png` | **036** "Sin resultados." con el teclado abierto · **037** caso con producto elegido |
| `UI-07-compra-form-inicial.png` | **037**, **038**, **039**, **040**, **041**, **064** — los seis se ven en el estado inicial del formulario |
| `UIBUG-042-043-aplicacion-fila-agregada.png` | **042** elegir agrega · **043** la fila nace desplegada |
| `UIBUG-044-stock-negativo.png` | **044** stock proyectado negativo en rojo |
| `UIBUG-045-*.png` (7) | **045** ciclo de vida del plan: pendiente, aplicado, histórico, sin acción, segundo intento rechazado, persistencia, reversión que no reabre |
| `UIBUG-047-fab-global-no-crea-catalogos.png`, `UI-03-catalogos-*.png` | **047** una sola acción primaria; el FAB no ofrece ninguna creación de catálogo |
| `UIBUG-050-sin-respaldos.png` | **050** aviso informativo, no error |
| `UIBUG-059-*.png` (6) | **059** campaña cerrada terminal: menús por estado, confirmación, cierre y persistencia |
| `UIBUG-060-transferencia-sin-origen.png` | **060** sin origen no hay cero engañoso |
| `UIBUG-068-rail-130-horizontal.png`, `UIBUG-068-rail-desplazado.png` | **068** el rail no desborda y se desplaza · **063** etiquetas del rail |

## Respaldo 2.0 — ciclo completo

| Archivo | Paso |
|---|---|
| `UI-06-factura-antes-del-respaldo.png` | la fotografía de factura se abre **antes** del respaldo |
| `BACKUP-01-exportado.png` | exportación del contenedor `.agrobackup` |
| `BACKUP-02-lista-de-respaldos.png` | el listado ofrece **los dos formatos**: `.agrobackup` (19 KB) y `.db` histórico (192 KB) |
| `BACKUP-03-confirmacion-restauracion.png` | la confirmación lee el manifiesto: esquema 6 y 1 fotografía |
| `BACKUP-04-restaurado.png` | restaurado, con la ruta de la copia de seguridad previa |
| `BACKUP-05-factura-restaurada-abierta.png` | **la fotografía borrada del teléfono vuelve del contenedor y se abre** |
| `BACKUP-06-legacy-confirmacion.png` | el `.db` histórico se reconoce como esquema 5 y avisa de que no trae fotografías |
| `BACKUP-07-legacy-aviso.png` | aviso posterior a la restauración legacy |

Secuencia comprobada: exportar → verificar el contenedor → añadir una persona (modificar la
base) → **borrar la fotografía del teléfono** → restaurar → base recuperada (7 personas,
`integrity_check ok`), fotografía de vuelta (5 849 bytes, tamaño original), rutas reapuntadas
→ **la factura se abre**.

## Accesibilidad y navegación

| Archivo | Comprobación |
|---|---|
| `A11Y-130-liquidacion.png` | fuente **130 %**: nombres con elipsis, cifras completas, barra en una línea |
| `A11Y-130-inicio-inventario.png` | fuente **130 %**: el inventario reflota sus cifras en vez de recortarlas |
| `A11Y-horizontal.png` | horizontal **con el defecto 068 visible** (`BOTTOM OVERFLOWED BY 90 PIXELS`) — se conserva como evidencia *antes* |
| `UIBUG-068-rail-130-horizontal.png` | horizontal + 130 % **corregido**: sin desbordamiento |
| `UIBUG-068-rail-desplazado.png` | el rail desplazado: "Cuentas" alcanzable |
| `NAV-back-jerarquico.png` | final del recorrido de Atrás; el detalle está en el informe (`dumpsys window`) |

## logcat al terminar

**0** `RenderFlex`/desbordamientos · **0** avisos de `setState() callback` · **0** errores
mostrados al usuario.

Los únicos errores registrados durante la sesión fueron los **dos rechazos intencionados** al
intentar reaplicar un plan ya aplicado, que es el comportamiento que se estaba comprobando.
