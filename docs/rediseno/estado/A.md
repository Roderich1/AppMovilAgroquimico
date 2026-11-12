# Estado de la sesión A

- Dueño del worktree: sesión proyectoagro-4d desde 2026-11-12 (hora local en el commit)
- Base incorporada: B0 (33e581f)

## Entregas listas

| n | SHA | Pantallas / rutas | Pruebas corridas | Capturas | Diferencias con la lámina |
|---|---|---|---|---|---|

## En curso

- Aplicación, paso 1 («Persona y chaco», lámina Aplicacion1/VozAplicacion).

## Solicitudes al orquestador

## Bloqueos y decisiones del autor

- **«Persona» en la aplicación (pendiente de confirmación del autor, no aceptada por él).** Comprobado el 2026-11-12 sobre B0 (`33e581f`):
  - `applications.person_id` es el dueño del chaco. Elegir un chaco fija la persona a su dueño, y cambiar de persona limpia el chaco y la mezcla (`application_form_screen.dart` `selectFarm`/`selectPerson`; voz: `_selectFarmForVoice`). Con un plan, la persona sale de `farms.owner_person_id` (`agro_repository.dart` `planForApplication`).
  - Se consumen sus existencias por FIFO (`availableProductsForOwner`; `inventory_movements.owner_person_id = person_id` en `_insertApplication`), y el cargo sigue su `settlement_policy` (`_chargeText`; `docs/architecture/D04_E15_*`). Al revertir, existencias y cargos vuelven a ella.
  - No se guarda quién ejecutó físicamente la aplicación. El contrato F04 la llama «el responsable» de la operación (`docs/architecture/F04_RF13_RF03_ACTOR_Y_TARDIAS.md`, `original_person_id`), y RN-35 la llama «quien aplica» (`docs/15_BUSINESS_RULES.md`).
  - Decisión del orquestador: se conserva el rótulo «Persona», con la línea secundaria neutra «Responsable del chaco · se usan sus productos». El modo propio («Aplica el titular») no cambia. No hay campo nuevo ni efecto distinto. Por eso no se usa «Quién aplicó» (lámina 3.1).

## Hallazgos fuera de alcance
