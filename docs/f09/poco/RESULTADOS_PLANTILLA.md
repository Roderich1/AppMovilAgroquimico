# Resultados de la prueba manual de la voz en el POCO (plantilla vacía)

Copie este archivo con la fecha real en el nombre (`RESULTADOS_POCO_AAAA-MM-DD.md`) y rellene la copia. Guion: [`GUION_PRUEBA_VOZ_POCO.md`](GUION_PRUEBA_VOZ_POCO.md).

La misma lista, en CSV: [`resultados_PLANTILLA.csv`](resultados_PLANTILLA.csv). Allí `resultado` vale `pasa`, `falla` o `no_ejecutado`.

**Exploración, no es #12.** No copie aquí lo que dijo ni lo que la app transcribió: sólo marque y anote observaciones cortas. Un paso que no se hizo se marca «No ejecutado», nunca «Pasa».

| Dato | Valor |
|---|---|
| Fecha real y hora de inicio | |
| Teléfono (modelo, Android) | POCO X5 Pro 5G `22101320G`, Android 12 |
| APK: commit | |
| APK: SHA-256 | |
| Cuenta DEMO usada (sin contraseña) | |
| «Revisar cada frase» | ☐ activada ☐ desactivada ☐ no aparece |

## Bloque 0. Preparación

- **P1** APK ARM64 con origen y evidencia: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **P2** Instalación (☐ adb ☐ `adb -r` ☐ a mano): ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **P3** Activación con red: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **P4** Datos sintéticos y 10 L de Herbicida DEMO: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **P5** Permiso de evaluación dado, 0 guardados: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **P6** Modo avión, Wi‑Fi y datos apagados, el navegador no carga: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **P7** Modelo disponible sin red, «Modo avión: activado.»: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **P8** Licencias visibles: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:

## Bloque A. Compra

- **A1** E1 → Herbicida DEMO 5 L, 120 Bs/L: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **A2** E2 → proveedor Agroinsumos DEMO (sintético): ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **A3** Corrección a mano a 4 L: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **A4** Dictar otra vez E1 conserva los 4 L: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **A5** Cancelar: ninguna compra, inventario igual: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **A6** Borrador nuevo vacío y repetición: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **A7** «Sí, pagué todo», paga el titular: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **A8** «Registrar compra» una vez, sin diálogo de descarte: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **A9** Una compra de 480 Bs pagada, Herbicida 14 L, guardados +2: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:

## Bloque B. Continuidad

- **B1** Captura nueva sin restos de la anterior: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **B2** «Un litro y medio» → 1,5 L y producto correcto: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **B3** Producto después de una pausa → Insecticida DEMO 3 L: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **B4** Silencio: sin texto y sin cambios: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **B5** «No, todavía no»: compra de 495 Bs sin pagar: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **B6** Cancelar durante la apertura: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **B7** Micrófono denegado: mensaje, sin atascarse: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **B8** Formulario manual completado, guardados sin cambio: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:

## Bloque C. Aplicación y planificación

- **C1** E5 → Chaco Norte DEMO, titular, Herbicida DEMO 2 L: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **C2** Corrección a mano a 1,5 L: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **C3** Cancelar: ninguna aplicación: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **C4** Una aplicación de 1,5 L, inventario −1,5 L: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **C5** E6 → 3 ha, 1 L/ha, 3 L: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **C6** Dosis a mano a 2 L/ha → 6 L: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **C7** Cancelar: ningún plan: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:
- **C8** Un plan con 2 L/ha y 6 L: ☐ Pasa ☐ Falla ☐ No ejecutado — Obs.:

## Cierre

- **Z1** Dictados guardados: N = ____ (se esperan 7) — Obs.:
- **Z2** ☐ Permiso retirado (todo borrado) ☐ Conservado para revisar; se borrará antes del ______
- **Z3** Red restaurada: ☐ Sí ☐ No

**Observaciones generales** (sin transcripciones):
