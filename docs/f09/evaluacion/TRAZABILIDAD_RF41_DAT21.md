# F09: verificación de RF-41 y DAT-21 en el Cap. III (A14)

- **Fecha real:** 2026-11-08 (Bolivia, UTC−4). Rama `docs/f09-protocolo-guion`, desde `27e9a4e`.
- **Resultado:** RF-41 y DAT-21 **existen** en la copia local del documento que citan #12, #17 y #167. Verificado el 2026-11-08 sobre esa copia.
- **Pendiente del autor:** confirmar que esa copia local es la versión entregada. Hasta entonces, la verificación vale para la copia, no para el documento entregado.

## 1. Dónde se buscó

| Fuente | Comando o método | Resultado |
|---|---|---|
| Repositorio Mobile, todas las ramas | `git log --all --oneline -S "RF-41"` | Sólo los commits de F09 de esta semana (`f08d820`, `2313fa9`, `be5e265`, `24e5897`, `27e9a4e`), que lo citan **según #167** |
| Repositorio Backend, todas las ramas | `git log --all --oneline -S "RF-41"` y `-S "DAT-21"` | Ninguno |
| `C:\Users\MSI\Documents\ProyectoDeGrado`, `Downloads` y `Desktop` | Lectura de `word/document.xml` de 448 `.docx` y de los `.md`, `.txt` y `.json`, sin abrir Word | Aparece en las versiones v1.18 a v1.22.1 del documento, en los borradores de conciliación del 2026-10-31 y en la exportación del Project |

## 2. Copia verificada

| Dato | Valor |
|---|---|
| Archivo | `C:\Users\MSI\Documents\ProyectoDeGrado\Word-mcp\salida\Proyecto_Grado_Rodrigo_Univalle_v1.22.1_DEPURADO.docx` |
| SHA-256 | `964286d1ebf7b56d3bd6693fc552efb18bdf30b274ab40a7afe32945961262de` (28 149 660 B) |
| Modificado | 2026-10-31 13:04 (hora local del archivo) |
| Por qué esta | Es el nombre que citan #12 (comentario del 2026-10-31), #17 y #167 |

## 3. Texto encontrado (literal)

**RF-41**, en la Tabla 3.23 «Requisitos funcionales de voz, histórico, reconciliación y estimación». Prioridad `Must`; vínculos RU-12, RU-10; RN-08, RN-10; CU-16; verificación T, I:

> Conservar, con consentimiento de la persona y únicamente para la evaluación, por cada dictado la transcripción obtenida, los campos propuestos y los campos finalmente confirmados o corregidos, sin almacenar el audio por defecto y sin incorporar esa evidencia a la información colectiva, de modo que pueda verificarse la proporción de transcripciones útiles y de campos correctos.

**DAT-21**, en la Tabla 3.27 «Requisitos de datos», «Evidencia de dictado para evaluación». Vínculos RU-10, RU-12 y RF-41; `DAT / Must`; verificación I/T:

> La evidencia de cada dictado deberá conservar, con consentimiento, la transcripción, los campos propuestos, los campos confirmados o corregidos y el resultado de la operación, sin audio por defecto y separada de la información colectiva.

**Otras menciones, en el mismo documento:**
- la introducción de los RF: «RF-35 a RF-41 especifican la estimación del consumo y la evidencia de la captura por voz»;
- la descripción de la figura 3.10 (panel c);
- 3.13.3, «Protocolo de voz (RNF-14)», que además define la transcripción útil (ver A11);
- las limitaciones: «RF-35 a RF-41 (estimación y evidencia de dictado) … no están construidos». Es el estado del documento entregado, anterior a esta implementación.

## 4. Diferencias con lo que dice #167

| Punto | Cap. III | #167 y código | Lectura |
|---|---|---|---|
| Vínculos | RF-41 también con RU-10, RN-08 y RN-10 | #167 cita RU-12, CU-16, RF-41, RNF-14 y DAT-21 | `Requirement refs` puede añadir RU-10, RN-08 y RN-10. Lo decide el autor |
| Referencia de la ficha | No la menciona RF-41; sí 3.13.3 («ficha fijada antes de hablar») | La tabla tiene `sheet_ref`, pero la app nunca la llena (A15) | Ninguna contradicción. Hoy el emparejamiento con la ficha es manual |
| Resultado de la operación | DAT-21 lo exige | Se guarda (`outcome`: confirmado, descartado o fallido) | Cumple |
| Respaldo privado | Ni RF-41 ni DAT-21 lo mencionan | Decisión del autor del 2026-10-31 en #167: fuera del respaldo | Es una regla adicional, no una contradicción |

## 5. Efecto

- RF-41 y DAT-21 pueden usarse en `Requirement refs` de #167 y #17, como ya figuran, citando la tabla y la versión del documento. Falta sólo que el autor confirme la versión (§2).
- `PROTOCOLO_Y_UMBRALES.md` (cabecera) y `README.md` remiten a esta nota. Los comentarios de código que dicen «pendientes de confirmar en el Cap. III» (`lib/voice_evidence/voice_evidence.dart:2-3`) no se tocan en esta rama.
