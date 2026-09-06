# Principios de evolución

## Reglas obligatorias

1. Partir de `main`; nunca mover ni modificar `v1.0.0-base-stable`.
2. Un cambio de capacidad por spec aprobada; separar refactors grandes.
3. Cambiar lo mínimo que satisfaga el contrato y dejar una ruta de reversión.
4. Preservar datos: migraciones forward-only, idempotentes en su ámbito y sin resets.
5. Mantener equivalencia entre base nueva y base migrada.
6. Proteger reglas críticas en dominio/transacción/constraint, no sólo en UI.
7. Reutilizar dinero, cantidades y búsqueda centrales; no crear parsers locales.
8. Mantener offline-first salvo decisión explícita. Una caída externa no debe bloquear el
   trabajo local cuando la capacidad pueda degradarse de forma segura.
9. No romper `.agrobackup`; declarar compatibilidad y restauración antes de cambiar datos.
10. Tests y documentación viajan en el mismo PR que el comportamiento.
11. Todo plugin Android requiere prueba en dispositivo; todo cambio SQLite, prueba de migración.
12. Datos enviados fuera del teléfono requieren decisión, consentimiento y minimización.

## Secuencia estándar

`PROPOSED → ANALYZED → APPROVED → IN_PROGRESS → VERIFIED`.

No se salta `APPROVED`. Rechazo o aplazamiento conserva la traza mediante `REJECTED` o
`DEFERRED`.

## Umbrales para una frontera nueva

Crear servicio/interfaz cuando aparezca al menos una condición:

- usa filesystem, micrófono, red, background task o plugin nativo;
- tiene política de error/reintento propia;
- requiere un fake para pruebas deterministas;
- procesa datos sensibles fuera de SQLite;
- será compartido por más de una pantalla;
- cambia a un ritmo distinto del dominio contable.

No crear una capa sólo para reenviar una llamada.

## Política de refactor

- Oportunista: extraer el seam que la feature necesita y cubrirlo antes/después.
- Dirigido: refactor separado cuando bloquea varias features o reduce un riesgo alto.
- Prohibido: reordenar todo el proyecto, cambiar state management o ORM dentro de una feature
  sin necesidad demostrada y ADR aceptado.

## Compatibilidad

- Código nuevo lee datos producidos por versiones anteriores soportadas.
- Backups antiguos aceptados siguen aceptándose salvo decisión de producto y plan de salida.
- Un cambio irreversible debe tener preflight, backup recomendado, mensajes claros y evidencia.
