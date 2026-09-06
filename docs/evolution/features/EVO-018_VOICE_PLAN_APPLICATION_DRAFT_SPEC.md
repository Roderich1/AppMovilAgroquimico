# EVO-018 — Aplicar una planificación mediante borrador de voz

## Estado

`APPROVED`. Implementar después de `EVO-009` y `EVO-010`, separada de compra y pago.

## Objetivo

Localizar un plan pendiente, preparar su aplicación y permitir expresar cantidades reales por
voz sin alterar el plan, stock ni FIFO hasta la confirmación táctil.

## Selección de plan

La frase “Quiero aplicar la planificación para el chaco Limoncitos” busca únicamente planes:

- pendientes;
- de la campaña activa;
- correspondientes al chaco resuelto.

Si hay uno, se propone mostrando fecha, persona, chaco y líneas. Si hay varios, se muestran
opciones y se exige selección. Si no hay ninguno, se informa y no se transforma la frase en
una aplicación libre.

## Borrador

| Dato por línea | Contenido |
|---|---|
| Producto | El definido por el plan |
| Planeado | Cantidad original, inmutable en este flujo |
| Real | Inicialmente propuesta igual a planeado; editable |
| Diferencia | `real - planeado`, calculada |
| Stock actual | Lectura tipada antes de confirmar |
| Stock posterior | Proyección calculada, nunca escritura previa |

También muestra campaña, chaco, propietario/persona, fecha, área, notas y el plan seleccionado.

## Corrección conversacional

> “De Bellator en realidad usamos diez litros.”

Actualiza solamente la cantidad real de Bellator. Si dos líneas pueden coincidir, se pide
selección. Las correcciones manuales y por voz comparten validación.

## Confirmación

- Revalidar plan pendiente, campaña y stock inmediatamente antes de escribir.
- Convertir el draft revisado al contrato esperado por `confirmApplication()`.
- Usar `confirmApplication()` como autoridad de FIFO, costo, movimientos, stock y consumo
  one-shot del plan.
- Si el plan cambió o fue usado por otra acción, mostrar conflicto y conservar una copia del
  draft sólo para revisión; no crear una aplicación libre automáticamente.

## Bloqueos

- Chaco o plan ausente/ambiguo.
- Plan no pendiente o fuera de la campaña activa.
- Producto/cantidad/unidad inválida.
- Cantidad negativa o stock insuficiente.
- Datos requeridos por el contrato actual ausentes.

## Requisitos

- `EVO-018-REQ-001`: filtrar exactamente por pendiente + campaña activa + chaco.
- `EVO-018-REQ-002`: desambiguar varios planes visualmente.
- `EVO-018-REQ-003`: mostrar planeado, real, diferencia y stock posterior por línea.
- `EVO-018-REQ-004`: permitir correcciones sucesivas por voz y manuales.
- `EVO-018-REQ-005`: bloquear antes de escribir si el stock proyectado es insuficiente.
- `EVO-018-REQ-006`: confirmar una sola vez mediante `confirmApplication()`.
- `EVO-018-REQ-007`: no modificar ni marcar usado el plan al cancelar o fallar.

## Pruebas obligatorias

- Cero, uno y varios planes candidatos.
- Homónimos de chaco y nombres similares.
- Cantidad real igual, menor y mayor que la planeada.
- Stock exacto, insuficiente y cambiado entre preview y confirmación.
- Corrección por voz de una línea y edición manual de otra.
- Atomicidad/FIFO/costo idénticos al flujo manual.
- Doble confirmación y plan ya consumido.

