# EVOLUTION-3 — Devolución de las pruebas en teléfonos

Plantilla para registrar lo observado. Se copia y se completa; no hace falta
editar ningún otro documento técnico.

Instrucciones de ejecución: `EVOLUTION-3_OWNER_DEVICE_TEST_PLAN.md`.

> **Regla única de esta plantilla:** lo que no se probó se escribe
> `NO PROBADO`, y lo que no se pudo medir, `NOT_MEASURED`. Nunca se deja una
> celda en blanco ni se pone un cero de relleno. Un cero significa "medí y dio
> cero"; un hueco significa otra cosa completamente distinta, y confundirlos
> llevaría a elegir mal el motor.

---

## Identidad de la tanda

| Campo | Valor |
|---|---|
| Fecha |  |
| Quién ejecutó |  |
| APK usados (nombre y SHA-256) |  |
| Corpus (versión) |  |
| Archivos exportados adjuntos |  |

---

## Ficha por teléfono y motor

Copie este bloque una vez por cada combinación de teléfono y aplicación.
Con dos teléfonos y tres aplicaciones son seis bloques.

### Bloque _(teléfono N · motor M)_

| Campo | Resultado |
| --------------------- | --------- |
| Marca y modelo        |           |
| Procesador            |           |
| RAM                   |           |
| Android/API           |           |
| Motor                 |           |
| Modelo Whisper        |           |
| Tamaño APK            |           |
| Instalación correcta  |           |
| Funciona sin Internet |           |
| Locale solicitado     |           |
| Locale utilizado      |           |
| Frases correctas      |           |
| Frases con errores    |           |
| Latencia percibida    |           |
| Calentamiento         |           |
| Consumo de batería    |           |
| Errores observados    |           |
| Archivo de resultados |           |

#### Condiciones cubiertas

| Condición | ¿Se probó? | Qué se observó |
|---|---|---|
| Con Internet |  |  |
| Modo avión |  |  |
| Lugar silencioso |  |  |
| Con ruido de campo |  |  |
| Permiso denegado |  |  |
| Permiso concedido después de denegar |  |  |
| Llamada entrante o interrupción |  |  |
| Pantalla bloqueada mientras grababa |  |  |
| Segundo plano y regreso |  |  |
| Micrófono liberado al salir |  |  |
| Sesión larga (varias frases seguidas) |  |  |

#### Frases que fallaron

| Frase | Lo que dijo | Lo que entendió | Comentario |
|---|---|---|---|
|  |  |  |  |

> Interesa especialmente lo que **cambia un dato crítico**: producto por otro
> producto, `50` por `15`, litros por kilos, bolivianos por dólares, una persona
> por su homónimo. Un error de puntuación no importa; uno de cantidad sí.

---

## Checklist final de la tanda

Marque lo que corresponda:

- [ ] **Prueba completa** — se ejecutó el corpus de aceptación entero, en las
      condiciones previstas, con los dos teléfonos.
- [ ] **Prueba incompleta** — falta algo. Indicar qué:
      _______________________________________________
- [ ] **Motor no instalable** — indicar cuál y el error exacto:
      _______________________________________________
- [ ] **Motor no disponible** — se instaló pero el teléfono no ofrece
      reconocimiento, o no tiene el idioma. Indicar cuál:
      _______________________________________________
- [ ] **Error reproducible** — ocurre siempre con los mismos pasos. Describir:
      _______________________________________________
- [ ] **Evidencia exportada** — los archivos JSON/CSV están adjuntos.
- [ ] **Capturas** — de la pantalla de disponibilidad y de los errores.
- [ ] **Logcat** (opcional) — sólo si hubo un cierre inesperado.

### Observaciones libres

_______________________________________________________________

---

## Qué se hace con esto

1. Se juntan los archivos exportados en una carpeta.
2. Se genera la comparación:

   ```bash
   dart run tool/voice_benchmark/main.dart <carpeta> -o informe.md
   ```

3. Los números se incorporan a
   `EVOLUTION-3_SPEECH_ENGINE_BENCHMARK_RESULTS.md`.
4. Recién entonces se resuelve `ADR-002` (resuelto el 2026-09-06; ver abajo).

### Condiciones para aceptar `ADR-002` — cómo se resolvieron

`ADR-002` fue **aceptado el 2026-09-06**. Así quedó cada condición:

- [x] Resultados de un **Android de gama media o baja** — POCO X5 Pro 5G, API 31.
- [ ] Resultados del **Pixel 8 / API 36** — **`WAIVED_BY_OWNER`**, no ejecutado.
- [x] El motor elegido funciona **en modo avión**, verificado contra el sistema.
- [x] Se sabe qué locale usa: `es-US`. `es-BO` **no existe** y `es-ES` no estaba
      instalado.
- [x] Impacto en el tamaño de la aplicación: **0 bytes**.
- [ ] **Ningún dato crítico se transcribe mal de forma sistemática** — *no se
      cumple*: los nombres de producto fallan en los tres motores (5/17 el
      mejor). Aceptado explícitamente, porque ningún motor lo resuelve; se
      aborda en `EVO-010` contra el catálogo local.

Esta plantilla sigue vigente para futuras tandas de regresión, en particular si
aparece un teléfono con **Android 16 / API 36**.
