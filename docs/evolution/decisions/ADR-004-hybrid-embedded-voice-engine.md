# ADR-004 — Motor de voz híbrido y autocontenido

- Estado: `Proposed`.
- Fecha: 2026-09-07.
- Decisor: propietario del producto con evidencia técnica.
- Revisa: `ADR-002 — Motor de transcripción por voz`.
- No sustituye `ADR-002` mientras permanezca `Proposed`.

## Contexto

`ADR-002` eligió Android `SpeechRecognizer` después de medirlo frente a Whisper tiny y base
en un POCO X5 Pro con Android 12/API 31. Fue el mejor candidato medido, funcionó en modo avión,
dio resultados parciales, tuvo menor latencia y no afirmó texto sobre silencio.

La prueba posterior en un HONOR JDY-LX3P con Android 16/API 36 reveló una dependencia que el
primer dispositivo no exponía:

- el reconocedor on-device existe, pero no tiene un modelo de español instalado;
- el reconocedor predeterminado también devuelve error 13 para los españoles probados;
- el sistema no ofrece a la aplicación una ruta exportada para instalar el modelo;
- sin Gboard no hay una entrada accesible al gestor privado de paquetes de idioma;
- el resultado depende del OEM, del proveedor del servicio y de modelos externos a la app.

Por tanto, el disparador de reconsideración definido en `ADR-002` se cumplió: el motor elegido
no funciona en una parte de los dispositivos reales aunque la API declare disponibilidad.

## Objetivos

1. Funcionar completamente sin Internet desde la primera instalación útil.
2. Evitar depender de Gboard, Google app, Android System Intelligence u otro paquete de idioma.
3. Mostrar texto parcial con rapidez mientras el usuario habla.
4. Obtener una transcripción final más precisa para frases largas.
5. Mejorar nombres agrícolas mediante vocabulario local sin permitir que el motor invente datos.
6. Mantener ingreso manual, borrador editable y confirmación humana.
7. Mantener el motor detrás de `SpeechTranscriptionPort`.

## Alternativa propuesta

Adoptar, sujeto a benchmark, una canalización local híbrida:

```text
AudioRecord nativo, PCM 16 kHz mono
        ├── Vosk móvil → parciales rápidos y no autoritativos
        └── buffer acotado → Whisper small-q5_1 → texto final propuesto
```

### Roles

- **Vosk**: experiencia en vivo, detección temprana de frases cortas y vocabulario restringido o
  adaptable. Sus parciales nunca disparan navegación ni operaciones.
- **Whisper small-q5_1**: segunda pasada al detenerse o al cerrar un segmento; produce el texto
  final propuesto para la vista previa.
- **Resolución local de `EVO-010`**: decide candidatos de producto, persona, chaco, proveedor,
  cantidades y montos. Ningún motor ASR entrega entidades confiables directamente.
- **Usuario**: corrige y confirma. La voz nunca confirma una operación.

## Candidatos exactos iniciales

| Componente | Candidato | Estado |
|---|---|---|
| Parciales | `vosk-model-small-es-0.42` | Candidato oficial móvil; validar licencia, hash y exactitud del corpus agrícola |
| Final | `ggml-small-q5_1.bin` para `whisper.cpp` | Candidato cuantizado; validar versión, hash, latencia, memoria, silencio y temperatura |
| Sistema | Android `SpeechRecognizer` | Control histórico y fallback opcional; no dependencia obligatoria |

No se acepta la descripción “Vosk español de 180 MB” sin nombre, URL oficial, licencia,
versión y SHA-256. La lista oficial actual identifica el modelo móvil español como 39 MB y el
modelo grande como 1,4 GB; este último está orientado a servidor.

## Restricciones arquitectónicas

1. Una sola captura del micrófono. No abrir `AudioRecord` y `SpeechRecognizer` simultáneamente.
2. El audio permanece en memoria nativa; no cruza a Dart y no se escribe en archivos.
3. PCM: 16 kHz, mono, 16 bits, salvo evidencia que obligue a cambiarlo.
4. Duración máxima configurable, inicialmente 90 segundos.
5. Buffer máximo aproximado a 90 segundos: 2,88 MB de PCM, liberado al cancelar, cerrar o fallar.
6. Vosk recibe fragmentos durante la captura.
7. Whisper empieza después de cerrar el segmento; no ejecuta una segunda captura.
8. Sólo un motor pesado puede inferir a la vez.
9. Todo código nativo debe tener lifecycle explícito: initialize, start, stop, cancel, close.
10. Toda memoria y handle nativo se libera de forma idempotente.
11. No ejecutar inferencia en el hilo principal.
12. Cancelar una sesión invalida callbacks tardíos mediante session token/generation ID.
13. El resultado parcial y el final viven separados; el final no sobrescribe una edición manual.
14. Silencio o VAD insuficiente produce `noSpeech`, nunca texto aceptable automáticamente.
15. Texto como `[MÚSICA]`, repeticiones degeneradas y salida sin habla deben marcarse como
    sospechosos, no agregarse silenciosamente.

## Estrategia de UX propuesta

1. El usuario toca una vez el micrófono.
2. Vosk muestra parciales rápidos identificados como provisionales.
3. Al detectar pausa o al pulsar detener, la UI muestra “Revisando transcripción…”.
4. Whisper procesa el mismo audio y devuelve el texto final propuesto.
5. Si Vosk y Whisper discrepan en números, monedas, productos o personas, la UI marca la parte
   como “Revisar”, sin elegir silenciosamente.
6. El usuario puede aceptar el texto, seguir hablando, editarlo o descartarlo.
7. `EVO-010` recibe únicamente texto final revisable y metadatos de incertidumbre.

## Distribución propuesta

No se decide todavía entre empaquetar todos los modelos o instalarlos como paquete adicional.
Se medirán dos alternativas:

- **Bundle autocontenido**: funciona desde la instalación y no depende de red, con APK grande.
- **Paquete de voz verificable**: modelo descargado o importado antes de ir al campo, con
  SHA-256, instalación atómica, versión visible y eliminación/reinstalación controladas.

El paquete de voz nunca puede descargarse silenciosamente ni quedar parcialmente instalado.
Si falta o está corrupto, la aplicación manual sigue funcionando.

## Criterios para aceptar este ADR

El ADR sólo puede pasar a `Accepted` si el benchmark demuestra en POCO API 31 y HONOR API 36:

- Vosk entrega primer parcial p50 <= 800 ms y p95 <= 1500 ms;
- Whisper small finaliza p50 <= 2500 ms y p95 <= 5000 ms para frases de hasta 20 s;
- factor de tiempo real de Whisper p95 <= 0,50 en frases de hasta 60 s;
- memoria pico total <= 1,2 GB;
- ninguna caída, ANR u OOM en 30 sesiones consecutivas;
- aumento térmico y throttling documentados en 10 minutos de uso repetido;
- cero texto aceptado en todas las muestras de silencio y ruido sin voz;
- mejora estadísticamente visible en datos críticos frente a Android del corpus anterior;
- cantidades, montos y unidades no empeoran respecto del mejor baseline;
- modelos, binarios, licencias, versiones y hashes son reproducibles;
- funcionamiento en modo avión desde una instalación limpia;
- ingreso manual y cero escrituras de negocio conservados.

Los umbrales pueden cambiar antes del benchmark, pero no después de ver los resultados sin
registrar y justificar la modificación.

## Consecuencias si se acepta

- `ADR-002` queda `Superseded by ADR-004`, sin borrar su evidencia.
- Android `SpeechRecognizer` deja de ser requisito productivo; puede quedar como fallback
  opcional únicamente si la política de privacidad lo autoriza.
- `EVO-009` conserva UI, sesión, permisos, continuidad y el puerto existentes; se reemplaza el
  adaptador y se amplía el contrato para parciales/finales híbridos.
- Aumentan tamaño, complejidad nativa, tiempo de build y superficie de supply chain.
- Se obtiene independencia respecto a modelos del OEM y mejor capacidad de vocabulario local.

## Condiciones de rechazo

Rechazar o reformular el híbrido si Whisper small no cumple latencia/temperatura, si ejecutar
ambos motores causa OOM o degradación sostenida, si Vosk no mejora la experiencia parcial, si
la distribución del modelo no es operativamente viable o si las licencias/procedencia no quedan
cerradas.

