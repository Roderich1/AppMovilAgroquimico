# F09: evaluación de la voz y evidencia con consentimiento (#12, #167)

- **Fecha real:** 2026-11-08. Rama `feat/f09-c-evidencia`, desde `49108ba`. Sin push.
- **Estado:** preparación. **Ninguna toma ejecutada, ningún resultado.** La evidencia local está implementada y probada en HOST; no está conectada a las pantallas (lo hace la coordinadora) y no se ha probado en emulador ni en teléfono (`NOT_RUN`).

| Archivo | Qué es |
|---|---|
| [`PROTOCOLO_Y_UMBRALES.md`](PROTOCOLO_Y_UMBRALES.md) | Copia literal de las definiciones D1–D6 y los umbrales de c-12, citas de ADR-004 (`Proposed`) y del plan del ensayo, y la lista de lo ambiguo o pendiente (A1–A14) |
| [`PLANTILLA_REGISTRO.md`](PLANTILLA_REGISTRO.md) · [`registro_tomas_PLANTILLA.csv`](registro_tomas_PLANTILLA.csv) | Registro por toma y por sesión |
| [`FRASES_Y_HOLDOUT.md`](FRASES_Y_HOLDOUT.md) | Frases de ajuste (expuestas), frases de aceptación (vacío: las escribe el autor o un tercero) y procedimiento del hash |
| [`metricas/f09_metricas.py`](metricas/f09_metricas.py) | Cálculo de las métricas por teléfono y condición. Pruebas: `python -I -B -m unittest discover -s docs/f09/evaluacion/metricas -p "test_*.py"`, con datos **sintéticos** |

## Evidencia de dictado en el teléfono (#167)

Código en `lib/voice_evidence/`, tablas en la versión 14 del esquema (`AppDatabase.voiceEvidenceSchema`).

- **Consentimiento** (`voice_evidence_consent`): explícito, sólo para la evaluación (`F09_VOICE_EVALUATION`), con la versión del texto aceptado y la fecha. Independiente del permiso del micrófono y de cualquier otro consentimiento. Revocable.
- **Sin consentimiento no se guarda nada**: se comprueba dentro de la misma transacción que escribiría. Un dictado que empezó antes del consentimiento vigente tampoco se guarda.
- **Qué se guarda** (`voice_evidence`), por borrador terminado: referencia de la ficha, transcripción de cada dictado, campos propuestos por la voz, correcciones y campos confirmados **en columnas separadas**, resultado (confirmado, descartado o fallido), motor, modelo, commit y tiempos si se conocen.
- **Nunca audio**: no hay columna binaria ni parámetro de audio.
- **Borrado**: retirar el consentimiento borra todo; también se puede borrar toda la evidencia o una entrada. Con `secure_delete`, para que el texto no quede en páginas libres.
- **Fuera del respaldo privado F08**: se borra de la copia que se empaqueta (y se compacta con `VACUUM`) y de la base restaurada. Un consentimiento tampoco viaja ni se restaura.
- **Fuera de Sync v1 y de lo colectivo**: Sync v1 sólo envía filas de `sync_outbox`; la evidencia no escribe en ella y ningún código de sincronización nombra sus tablas (prueba de guarda).

**Limitaciones declaradas:**
- La copia previa `.previo` que se hace antes de una restauración (F08-ADR-003 §7, hasta 7 días, carpeta privada excluida del auto-backup de Android) es una copia exacta de la base anterior y **sí contiene la evidencia** que hubiera. Borrar la evidencia no la alcanza. No se toca: la recuperación compara su SHA-256.
- Restaurar un respaldo sustituye la base entera: la evidencia que hubiera en el teléfono antes de restaurar también desaparece de la base activa.
- La entrega al evaluador es la lectura en el propio teléfono (`VoiceEvidenceStore.readAll`). No hay exportación: #167 la deja fuera de alcance.

## Texto de consentimiento: propuesta pendiente del autor

**No usar con participantes sin la aprobación de Roderich.** El código sólo exige que la pantalla guarde un identificador de la versión del texto que la persona aceptó.

> Para evaluar la voz de Agrocuentas, ¿permite que este teléfono guarde, por cada dictado, el texto reconocido, lo que la app propuso, lo que usted corrigió y lo que confirmó? No se graba su voz. Estos datos se quedan sólo en este teléfono: no se envían al sindicato, no entran en el respaldo y se usan sólo para la evaluación. Puede retirar el permiso cuando quiera y se borrará todo lo guardado.
