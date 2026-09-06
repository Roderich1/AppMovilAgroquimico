# EVO-010 — Interpretación de voz y borrador tipado

## Estado y decisión

- Estado: `APPROVED`.
- Etapa: `EVOLUTION-3`.
- Depende de: `EVO-009` verificada o integrada con sus gates verdes.
- Alcance: convertir texto de sesión en una intención soportada y un borrador tipado.
- Límite: interpretar nunca equivale a ejecutar.

## Flujo

```text
SpeechTranscriptionPort
  → VoiceSessionController
  → VoiceIntentClassifier
  → VoiceEntityExtractor
  → CatalogResolver
  → TypedVoiceDraft
  → DraftValidator
  → UI de revisión
```

Ningún componente anterior conoce `Database`, SQL, FIFO ni métodos de escritura. La UI de
confirmación entrega un comando tipado al caso de uso existente sólo cuando el borrador es
válido y el usuario pulsa el botón específico.

## Intenciones de esta etapa

| Código | Resultado tipado | Feature ejecutora |
|---|---|---|
| `purchase.register` | `VoicePurchaseDraft` | `EVO-017` |
| `planned_application.confirm` | `VoicePlannedApplicationDraft` | `EVO-018` |
| `account.payment.register` | `VoicePaymentDraft` | `EVO-019` |
| desconocida | `UnsupportedVoiceIntent` | Ninguna |
| ambigua/múltiple | `AmbiguousVoiceIntent` | Ninguna |

## Estados de resolución

Cada referencia de catálogo conserva texto original, candidatos y estado:

- `resolved`: coincidencia inequívoca elegida.
- `ambiguous`: dos o más candidatos; requiere selección.
- `newProposed`: sólo para producto/proveedor donde la feature lo permita; requiere revisión.
- `missing`: no fue mencionado y no existe un default permitido.
- `invalid`: se mencionó, pero no cumple formato o regla.

No se elegirá automáticamente entre personas homónimas, planes múltiples o productos de
similar puntuación. La confianza del transcriptor es información auxiliar, nunca permiso para
confirmar.

## Actualización conversacional

Una intervención posterior se aplica como parche sobre el borrador actual:

- completa un campo faltante;
- corrige un valor cuando el usuario expresa corrección (`en realidad`, `corrige`, `no...`);
- añade líneas a una compra;
- cambia una cantidad real de una aplicación;
- sustituye una selección después de confirmación visual.

El historial de cambios vive en memoria durante la sesión para permitir deshacer la última
edición. Si el nuevo texto parece iniciar otra operación, la app pregunta si se descarta el
borrador actual.

## Números, unidades y dinero

- Reutilizar el parser y políticas numéricas centrales; no crear aritmética con `double`.
- Cantidades e importes se convierten a los enteros/base units del dominio.
- Mostrar siempre unidad, moneda y precio interpretados.
- Expresiones incompletas (`a ciento ochenta`) quedan ambiguas entre precio total/unitario si
  el contexto no lo determina.
- Fechas relativas se resuelven en la zona horaria del dispositivo y quedan visibles.

## Alias y catálogo

Los alias son datos locales normalizados asociados a una entidad, no reemplazos destructivos
del nombre. Ejemplos:

| Producto | Alias iniciales |
|---|---|
| Germi-100 | `germi cien`, `germi uno cero cero` |
| Expansive | `expansiv`, `expansive` |

Los alias sugeridos por transcripciones pueden guardarse sólo mediante acción explícita. Nunca
se agrega un alias silenciosamente a partir de una única frase.

## Requisitos

- `EVO-010-REQ-001`: producir uno de los estados tipados definidos.
- `EVO-010-REQ-002`: conservar el texto original para explicar cada campo durante la sesión.
- `EVO-010-REQ-003`: bloquear todo dato crítico ambiguo, inválido o faltante.
- `EVO-010-REQ-004`: admitir parches sucesivos por voz y edición manual sobre el mismo draft.
- `EVO-010-REQ-005`: no importar repositorios de escritura desde clasificación/extracción.
- `EVO-010-REQ-006`: permitir un fake determinista para corpus y widget tests.
- `EVO-010-REQ-007`: no registrar transcripciones completas ni datos sensibles en logs.

## Aceptación

- Las frases de compra, aplicación y pago del corpus producen drafts reproducibles.
- Homónimos, baja confianza y unidades/monedas ambiguas no se autoresuelven.
- Corregir por voz cambia sólo los campos aludidos.
- Un intent desconocido explica las tres acciones disponibles y no crea borrador ejecutable.
- Cero métodos de escritura llamados durante captura, interpretación, edición o descarte.

