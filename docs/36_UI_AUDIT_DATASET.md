# 36 — Dataset de la auditoría de interfaz

Estrategia, contenido y procedimiento de recarga del conjunto de datos usado para auditar la
aplicación sobre el emulador **Pixel 8**.

> **Este dataset no es de producción.** Todos los nombres son ficticios y no corresponden a
> ninguna persona real. Ningún archivo de esta infraestructura se compila dentro de la app.

## 1. Estrategia de carga

Se descartó insertar SQL directamente y se descartó cualquier `if (kDebugMode) seed()` dentro
de `lib/`. El dataset se construye **llamando a los métodos reales de `AgroRepository`**, de
modo que respeta exactamente las mismas reglas que aplicaría un usuario:

| Regla real que el seed está obligado a cumplir | Dónde la impone el repositorio |
|---|---|
| Solo se puede comprar/aplicar/planificar sobre la campaña **ACTIVE** | `_ensureCampaignActive` |
| Las asignaciones de una línea deben sumar exactamente la cantidad comprada | `confirmPurchase` |
| No se puede aplicar más stock del disponible | `confirmApplication` |
| El consumo sigue FIFO por lote | `confirmApplication` |
| Origen ≠ destino y sin productos repetidos en una transferencia | `transferProductsFifo` |
| Una reversión exige que los lotes movidos sigan intactos | `reverseTransfer`, `reversePurchase` |
| `FAMILY` se carga al aplicar; `THIRD_PARTY` al comprar | política de la persona |

Si alguna de esas reglas cambia, el generador **falla** en lugar de producir datos imposibles.

## 2. Archivos creados

| Archivo | Qué es | ¿Conservar? |
|---|---|---|
| `test/support/ui_audit_seed.dart` | Biblioteca con `seedUiAudit(repo)`. Vive en `test/` y **no** coincide con `*_test.dart`, por lo que `flutter test` no lo ejecuta como suite. | Sí — herramienta de desarrollo reutilizable |
| `tool/seed_ui_audit.dart` | Generador ejecutable. Crea `build/ui_audit/agroquimicos_v2.db` y la imagen de factura sintética. | Sí — herramienta de desarrollo |
| `tool/ui_audit_push.sh` | RESET → SEED → instalación en el dispositivo. | Sí — herramienta de desarrollo |

**Ninguno de los tres es referenciado desde `lib/`.** El código de producción no fue modificado
en esta fase (ver §7).

## 3. Procedimiento RESET → SEED → AUDIT

```sh
# 1. Regenerar el archivo desde cero e instalarlo en el emulador
bash tool/ui_audit_push.sh

# 2. Reinstalar el dataset ya generado (más rápido, mismo estado exacto)
bash tool/ui_audit_push.sh --no-seed

# 3. Además, reinstalar el APK de depuración
bash tool/ui_audit_push.sh --apk
```

El script detiene la app, copia la base dentro del *sandbox* con `run-as`, **borra los diarios
`-wal`/`-shm`** de la base anterior (pertenecen a otro archivo y la corromperían), copia la
fotografía de factura y vuelve a arrancar la aplicación.

Requiere un APK de **depuración** instalado: `run-as` solo funciona sobre paquetes depurables.

> **Nota de implementación.** El generador resuelve la ruta de salida a **absoluta** de forma
> deliberada: `sqflite_common_ffi` reubica las rutas relativas bajo
> `.dart_tool/sqflite_common_ffi/databases/`, con lo que el RESET no borraría el archivo que
> realmente se abre y las ejecuciones se acumularían unas sobre otras. Este error se detectó y
> se corrigió durante la preparación del dataset.

## 4. Contenido del dataset

| Entidad | Cantidad |
|---|---:|
| Personas | 7 |
| Chacos | 8 |
| Productos | 22 |
| Proveedores | 4 |
| Campañas | 3 |
| Compras | 10 |
| Transferencias | 7 |
| Aplicaciones | 12 |
| Planes | 5 |
| Pagos a proveedor | 4 |
| Pagos de cuenta | 5 |
| Compras revertidas | 1 |
| Transferencias revertidas | 1 |
| Aplicaciones revertidas | 1 |

Esquema resultante: **v5**. Archivo: ~192 KB.

### Personas (7)

Cubren nombre corto, nombre compuesto largo, y caracteres del español (`ñ`, tildes):

| Nombre | Rol |
|---|---|
| Administración Central | ADMIN |
| Juan Pérez | FAMILY |
| María Fernanda Rodríguez Salvatierra | FAMILY |
| José Luis Ñáñez Álvarez | FAMILY |
| Ana Áñez | FAMILY |
| Cooperativa Agrícola San Julián Ltda. | THIRD_PARTY |
| Pedro Áñez Suárez | THIRD_PARTY |

### Chacos (8)

Superficies elegidas para ejercitar el formateo de hectáreas: **0,3 ha**, 2,5 ha, 9,5 ha,
15 ha, 50 ha, 80 ha, 120 ha y **250 ha**. Incluye el nombre largo *"Hacienda Santa María de los
Ángeles del Norte Grande"*.

### Productos (22)

- Nombres cortos (`Urea`) y un **nombre muy largo** de 89 caracteres
  (*"Herbicida Selectivo Postemergente para Cultivos Extensivos Presentación Comercial Especial"*).
- **Nombres casi idénticos**: `Glifosato 48 SL` (L) y `Glifosato 68 SG` (KG).
- Ambas unidades, L y KG.
- **`Boro Quelatado`: nunca comprado** → debe seguir apareciendo en cero en los reportes.
- **`Zinc Quelatado`: comprado y consumido al 100 %** → stock exactamente cero.

22 productos bastan para forzar scroll en todas las listas y en todos los selectores (el
buscador del selector solo aparece a partir de 8 elementos).

### Campañas (3)

| Campaña | Estado | Para qué |
|---|---|---|
| Invierno 2025 | CLOSED | Historial real en una campaña ya cerrada |
| Verano 2026 | ACTIVE | Campaña de trabajo |
| Verano 2027 | PLANNED | Tercer estado |

El orden importa: se trabaja Invierno 2025, se cierra con `activateCampaign(closeCurrent: true)`
y recién entonces se opera sobre Verano 2026.

### Compras (10)

Cubren: compra pequeña de un producto; compra mediana de 5; **compra grande de 8 líneas**;
dos compras en **USD** con tipo de cambio 6,96 y 6,97; dos proveedores de razón social larga;
notas largas; y dos compras con **fotografía de factura**.

### Datos límite deliberados

| Caso | Valor | Qué estresa |
|---|---|---|
| Cantidad muy grande | 99 999,750 kg de Fosfato Diamónico | Separadores de miles y ancho de columna |
| Importe muy grande | 1 L de Tebuconazole a **9 999 999,99 Bs** | Overflow y truncamiento de importes |
| Decimal pequeño | 0,125 L de Glifosato 48 SL | Redondeo y decimales |
| Decimal con .75 | 99,75 L de Cipermetrina | Decimales no triviales |
| Superficie decimal | Chaco Chico, 0,3 ha | Formateo de hectáreas |
| Texto largo | Nota de aplicación de 4 líneas | Ajuste de texto en bitácora |

Todos son **valores válidos** según las reglas del dominio: no se introdujo ningún dato
inválido para forzar un fallo.

### Fotografía de factura

`tool/seed_ui_audit.dart` genera un **PNG sintético de 900×1200** (bandas de color con marco,
construido byte a byte con `ZLibCodec` y CRC-32, sin dependencias nuevas) y lo copia a
`app_flutter/invoices/invoice_ui_audit.png` dentro del sandbox. Dos compras apuntan a él.

No contiene información de nadie: son bandas de color, suficientes para comprobar orientación,
recorte y zoom.

> **Hallazgo relacionado:** esa fotografía **no puede verse desde la aplicación**, porque el
> visor de facturas vive en `PurchasesScreen` y esa pantalla es inalcanzable
> (ver `38_UI_AUDIT_FINDINGS.md`, UIBUG-002).

## 5. Ajuste hecho al dataset durante su construcción

El primer intento de seed falló con *"Stock insuficiente para confirmar la aplicación."*: se
pedía aplicar 120 L de Glifosato 48 SL cuando Juan Pérez solo tenía 100 L en ese momento. Se
corrigió reduciendo la aplicación a **80 L frente a 125 L teóricos**, lo que además deja una
varianza real visible en la bitácora y en el reporte de plan. El fallo fue del dataset, no de
la aplicación.

## 6. Verificaciones automáticas del generador

`tool/seed_ui_audit.dart` comprueba tras generar:

- 7 personas, 22 productos, 8 chacos, 3 campañas, 10 compras, 5 planes, 12 aplicaciones y
  7 transferencias;
- que exista al menos un producto con stock **cero** (para que los reportes no lo escondan).

Si el dataset deja de ser representativo, el generador **falla** en lugar de producir una
auditoría sobre datos silenciosamente incompletos.

## 7. Confirmación

Durante la preparación y la ejecución de la auditoría **no se modificó ningún archivo de
`lib/`**. Los únicos archivos nuevos son los tres de la §2, más las capturas en
`artifacts/ui-audit/` y los documentos `36`–`40`.
