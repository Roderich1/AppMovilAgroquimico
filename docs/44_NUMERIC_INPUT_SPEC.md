# 44 — Especificación de entrada numérica (es-BO)

Regla **única y centralizada** para interpretar todo número tecleado por el usuario.
Escrita **antes** de tocar `tryParseDecimal`, como exige el tratamiento especial de
[UIBUG-003](41_UIBUG_MASTER_BACKLOG.md).

Fecha: **2026-09-05** · Aplica a: `lib/domain/numeric_input.dart` (nuevo) y a sus
envoltorios en `lib/presentation/widgets/common.dart`.

---

## 1. El problema que esta especificación resuelve

La aplicación **imprime** con convenio es-BO (`NumberFormat(..., 'es_BO')` en
[money.dart](../lib/domain/money.dart)):

```
formatQuantity(15000000, 'KG')  ->  "15.000 KG"      punto = MILES
formatBob(150000)               ->  "Bs 1.500,00"    coma  = DECIMALES
```

pero **leía** con convenio inglés (`common.dart:131`):

```dart
final normalized = value.trim().replaceAll(' ', '').replaceAll(',', '.');
return num.tryParse(normalized);   // el punto es SIEMPRE decimal
```

Consecuencia verificada en dispositivo: el usuario lee *"15.000 KG disponibles"*, teclea
`15.000` y la aplicación entiende **15**. En el diálogo de pago, `1.500` se guardó como
**1,50 Bs** en lugar de 1.500,00 Bs. **Error de ×1000 en una aplicación de contabilidad.**

> ### Objetivo rector
> **La aplicación nunca debe interpretar en silencio un valor 1000 veces distinto del que el
> usuario probablemente quiso escribir.** Ante una cadena genuinamente ambigua, **rechazar
> explícitamente es mejor que adivinar.**

## 2. Convenio adoptado: es-BO estricto

| Símbolo | Papel | Ejemplo |
|---|---|---|
| `,` (coma) | **separador decimal** — el único | `1500,25` |
| `.` (punto) | **separador de miles** — nunca decimal | `1.500` |
| espacio | separador de miles alternativo | `15 000` |

El convenio de **entrada** es ahora idéntico al de **salida**. Lo que la aplicación imprime,
tecleado tal cual, se vuelve a interpretar como el mismo número. Esa es la invariante que
cierra UIBUG-003, y está cubierta por un test de ida y vuelta.

### Espacios aceptados como separador de miles

Se normalizan a espacio simple antes de analizar: espacio ` ` (U+0020), espacio duro
` ` (U+00A0) y espacio fino duro (U+202F). `NumberFormat` de `intl` emite U+00A0 en
algunos locales, de modo que el texto copiado de la propia aplicación debe volver a leerse.

## 3. Gramática aceptada

Tras recortar espacios exteriores y normalizar los espacios interiores, se acepta
**exactamente** esto:

```
numero    := entero | entero "," decimales
entero    := digitos | grupos
grupos    := 1-3 digitos ( SEP 3 digitos )+        SEP = "." o " " (uno u otro, no mezclados)
decimales := 1 o mas digitos
```

- **No** se admite signo: todos los importes y cantidades del dominio son positivos
  (`divideRoundedHalfUp` ya rechaza negativos).
- **No** se admite notación científica.
- **No** se admite mezclar `.` y ` ` como separadores de grupo en la misma cadena.
- Un separador de grupo obliga a que **todos** los grupos siguientes tengan exactamente
  3 dígitos y el primero entre 1 y 3.

## 4. Tabla de decisión — casos exigidos

Los 12 casos que el encargo obliga a definir, más los límites del dataset de auditoría:

| Entrada | Resultado | Estado | Razón |
|---|---|---|---|
| `1500` | `1500` | ✅ ACEPTADO | entero simple |
| `1500,25` | `1500.25` | ✅ ACEPTADO | coma decimal es-BO |
| `1.500` | `1500` | ✅ ACEPTADO | punto de miles es-BO. **Este es el caso de UIBUG-003.** |
| `1.500,25` | `1500.25` | ✅ ACEPTADO | miles + decimales es-BO |
| `15 000` | `15000` | ✅ ACEPTADO | espacio de miles |
| `15 000,75` | `15000.75` | ✅ ACEPTADO | espacio de miles + decimales |
| `0,125` | `0.125` | ✅ ACEPTADO | decimal; parte entera `0` no puede ser agrupamiento inglés |
| `99999,750` | `99999.75` | ✅ ACEPTADO | parte entera de 5 dígitos: no puede ser agrupamiento |
| `9.999.999,99` | `9999999.99` | ✅ ACEPTADO | grupos válidos + decimales |
| `1500.25` | — | ❌ **RECHAZADO** `malformed` | el punto es de miles; `.25` no es un grupo de 3 |
| `0.125` | — | ❌ **RECHAZADO** `malformed` | `0.125` como miles daría `0125`, agrupamiento inválido |
| `1,500.25` | — | ❌ **RECHAZADO** `malformed` | orden inglés (coma miles, punto decimal): no es es-BO |
| `1,500` | — | ⚠️ **RECHAZADO** `ambiguous` | **ver §5** |

### Otros límites cubiertos

| Entrada | Resultado | Estado |
|---|---|---|
| `` (vacío) / `   ` | — | `empty` (no es error: campo sin rellenar) |
| `abc`, `12abc`, `--5`, `1e3` | — | `malformed` |
| `-5` | — | `malformed` (sin signo en el dominio) |
| `1.5` | — | `malformed` (grupo de 1 dígito) |
| `1.5000` | — | `malformed` (grupo de 4 dígitos) |
| `12.34.56` | — | `malformed` |
| `1.500 000` | — | `malformed` (mezcla `.` y espacio) |
| `1,5` | `1.5` | ✅ ACEPTADO (1 decimal, sin colisión con agrupamiento) |
| `1,50` | `1.5` | ✅ ACEPTADO (2 decimales) |
| `1234,500` | `1234.5` | ✅ ACEPTADO (parte entera de 4 dígitos) |
| `0,001` | `0.001` | ✅ ACEPTADO |

## 5. La única ambigüedad real: `1,500`

`1,500` colisiona entre dos lecturas plausibles:

| Lectura | Valor | Convenio |
|---|---|---|
| coma decimal (es-BO) | `1.5` | el de la aplicación |
| coma de miles (en-US) | `1500` | el que teclea quien viene de Excel o de un teclado en inglés |

**Entre ambas hay exactamente un factor 1000**, que es justo el error que UIBUG-003 documenta.
Adivinar cualquiera de las dos puede producir un asiento contable mil veces equivocado sin que
nadie lo note.

**Decisión: rechazar explícitamente** con un mensaje que ofrece las dos formas no ambiguas.

### Criterio preciso de ambigüedad

Una cadena es `ambiguous` si y solo si cumple **todo** lo siguiente:

1. tiene la forma `^\d{1,3},\d{3}$` — una sola coma, exactamente 3 dígitos detrás;
2. la parte entera **no** empieza por `0`;
3. la parte entera **no** es `0`.

Las condiciones 2 y 3 son las que dejan pasar `0,125` (que sí debe aceptarse): como
agrupamiento inglés sería `0125`, con cero a la izquierda, y eso no es un agrupamiento válido
en ningún convenio. Por tanto `0,125` **solo** puede ser decimal y no hay ambigüedad.

Ejemplos del criterio:

| Entrada | ¿Ambigua? | Valor |
|---|---|---|
| `1,500` | **sí** | rechazada |
| `12,500` | **sí** | rechazada |
| `999,000` | **sí** | rechazada |
| `0,125` | no (parte entera es `0`) | `0.125` |
| `0,500` | no (parte entera es `0`) | `0.5` |
| `1234,500` | no (parte entera de 4 dígitos) | `1234.5` |
| `1,50` | no (2 decimales, no 3) | `1.5` |
| `1,5000` | no (4 decimales, no 3) | `1.5` |
| `1.500` | no (punto, no coma) | `1500` |

## 6. Mensajes de validación

Los tres mensajes son de usuario, en español, y **dicen qué hacer**:

| Estado | Mensaje |
|---|---|
| `ambiguous` | «"1,500" es ambiguo: escriba **1.500** si son miles, o **1,5** si es decimal.» *(el ejemplo se construye con la cadena real tecleada)* |
| `malformed` | «Escriba el número como **1.500,25**: use la coma para los decimales y el punto para los miles.» |
| `empty` | sin mensaje — un campo vacío no es un error de formato; lo valida la regla de negocio |

## 7. API centralizada

**Una sola implementación.** Ninguna pantalla parsea por su cuenta.

```dart
// lib/domain/numeric_input.dart
enum NumericInputStatus { empty, valid, ambiguous, malformed }

class NumericInputResult {
  final NumericInputStatus status;
  final num? value;      // no nulo si y solo si status == valid
  final String? message; // no nulo si ambiguous o malformed
  bool get isValid;
}

NumericInputResult parseNumericInput(String raw);
```

Envoltorios conservados en `common.dart` para no reescribir 26 llamadas:

| Función | Comportamiento nuevo |
|---|---|
| `tryParseDecimal(String)` | `num?` — **null salvo `valid`** (antes: null solo si `num.tryParse` fallaba) |
| `tryParseMinor(String)` | `int?` — céntimos, `×100` redondeado |
| `tryParseBase(String)` | `int?` — unidades base, `×1000` redondeado |
| `parseMinor(String)` | `int` — `tryParseMinor ?? 0` **(se conserva; ver §8)** |
| `parseBase(String)` | `int` — `tryParseBase ?? 0` |

## 8. Qué pasa con las entradas rechazadas en las pantallas

Hay 26 puntos de llamada. La mayoría usa `?? 0` para el **cálculo en vivo** mientras el usuario
teclea, lo cual es correcto: una cadena a medio escribir no debe romper la previsualización.

El riesgo no está en el cálculo en vivo sino en la **escritura**. Por eso:

1. **Toda cadena rechazada vale `0` en los cálculos en vivo** — nunca un valor 1000× distinto.
   Esto ya elimina la clase de error de UIBUG-003 incluso donde no hay validación explícita:
   antes `1.500` producía `1.5` (silenciosamente mal), ahora produce `1500` (correcto) y
   `1,500` produce `0` (visiblemente vacío), jamás `1.5`.
2. **En los puntos de escritura contable se valida explícitamente y se muestra el mensaje**:
   el diálogo de pago/adelanto de `settlements_screen.dart` (donde UIBUG-003 se materializó sin
   red de seguridad) y el de pago a proveedor de `purchases_screen.dart`. Ambos usan `parseMinor`,
   que es donde un `0` silencioso se convertía en el engañoso *"El importe debe ser mayor a cero"*
   de [UIBUG-065](41_UIBUG_MASTER_BACKLOG.md).
3. **Las reglas de negocio existentes siguen siendo la última red**: `addAccountPayment` rechaza
   `<= 0`, `confirmApplication` valida stock, `confirmPurchase` valida asignaciones. **No se
   cambia ninguna regla de negocio.**

## 9. Invariante de ida y vuelta

Verificada por test sobre todo el dominio de valores del dataset de auditoría:

```
para todo v: parseNumericInput(formatQuantity(v, u).sin_unidad).value == v / 1000
para todo v: parseNumericInput(formatBob(v).sin_simbolo).value      == v / 100
```

Es la garantía estructural de que UIBUG-003 no puede reaparecer: si alguien cambia el formato
de salida sin cambiar el de entrada, **el test se pone rojo**.

## 10. Qué NO cambia

- Ninguna regla de negocio ni fórmula de `money.dart`.
- Ningún formato de **salida** (eso es UIBUG-024/025/027/056, lote F, fuera de este batch).
- Ningún esquema de base de datos.
- No se añaden `TextInputFormatter` que impidan teclear: bloquear pulsaciones en un teclado
  numérico Android es frágil y no aporta sobre la validación en el envío. Se prefiere aceptar
  el texto y validarlo con un mensaje claro.
