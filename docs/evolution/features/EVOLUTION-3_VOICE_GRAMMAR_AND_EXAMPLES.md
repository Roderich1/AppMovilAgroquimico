# EVOLUTION-3 — Gramática funcional y ejemplos de voz

## Propósito

Este documento define lenguaje esperado para corpus, ejemplos de UI y pruebas. No obliga a
usar regex ni un modelo concreto; sí obliga a producir los mismos drafts tipados.

## Intenciones

| Intención | Inicios frecuentes |
|---|---|
| Compra | `registrar compra`, `compré`, `anota una compra`, `quiero registrar una compra` |
| Aplicar plan | `aplicar planificación`, `aplica el plan`, `usamos la planificación` |
| Pago | `registrar pago`, `me pagó`, `anota un pago para` |

Las palabras de cortesía o relleno no cambian la intención. Una frase sin intención clara no
crea un draft ejecutable.

## Componentes reconocibles

- Cantidades: `50`, `cincuenta`, `doce coma cinco` según precisión admitida por dominio.
- Unidades: litro/litros/L, kilo/kilos/kg y las existentes en catálogo.
- Dinero: `186 bolivianos`, `a 186 el litro`, `precio unitario 186`, `dólares`.
- Fechas: hoy, ayer, fecha explícita; siempre se muestran resueltas.
- Correcciones: `en realidad`, `corrige`, `cambia`, `no X, Y`.
- Agrupación: `todo para el administrador`; sólo aplica al alcance visible del draft.

## Alias de pronunciación

Normalizar mayúsculas, tildes, guiones y espacios para búsqueda, conservando el original. Un
alias nunca permite saltar desambiguación si coincide con más de una entidad.

| Nombre | Formas esperadas |
|---|---|
| Germi-100 | `germi cien`, `germi uno cero cero` |
| Expansive | `expansiv`, `expansive` |

La lista real se construye con los productos del usuario y un corpus de pronunciación local.

## Casos de corpus

### Compra completa

`Quiero registrar compra, cincuenta litros de Bellator a ciento ochenta y seis bolivianos el
litro. El proveedor es Agro Norte y todo para el administrador.`

### Compra incremental

1. `Quiero registrar una compra de cincuenta litros de Germispa.`
2. `El precio unitario es ciento ochenta y uno bolivianos.`
3. `El proveedor es Agro Norte.`
4. `Todo queda para José.`

### Corrección

`De Bellator no fueron doce, en realidad usamos diez litros.`

### Ambigüedad

`Registra un pago para José Luis de dos mil.` cuando existen dos José Luis.

### Fuera de alcance

`Borra la compra de ayer`, `cierra la campaña`, `transfiere todo`, `qué herbicida me
recomiendas`. La app explica que esa acción no está disponible por voz.

## Variaciones obligatorias de prueba

- Habla rápida/lenta, pausas y autocorrecciones.
- Ruido de campo, motor, viento y voces cercanas.
- Nombres regionales y distintos hablantes.
- Números seguidos de productos sin puntuación.
- Precio total frente a precio unitario.
- Unidad omitida o incompatible con el producto.
- Dos intenciones en una misma frase.
- Sesión interrumpida y reanudada.

