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
4. Recién entonces se resuelve `ADR-002`.

### Condiciones para que `ADR-002` pueda aceptarse

Todas, sin excepción:

- [ ] Hay resultados del **Pixel 8 / API 36**.
- [ ] Hay resultados de un **Android de gama media o baja**.
- [ ] El motor ganador funciona **en modo avión**, o queda documentado que no y
      el propietario acepta esa limitación por escrito.
- [ ] Se sabe qué locale usa realmente y si `es-BO` cae a otro.
- [ ] El impacto en el tamaño de la aplicación es aceptable para el propietario.
- [ ] Ningún dato crítico se transcribe mal de forma sistemática.

Si falta cualquiera, `ADR-002` permanece `Proposed`. No se elige motor "mientras
tanto".
