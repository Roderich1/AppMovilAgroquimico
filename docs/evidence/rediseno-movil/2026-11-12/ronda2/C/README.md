# Ronda 2 · sesión C · capturas y PDF (2026-11-12)

Arnés de pruebas, no un teléfono: la app real sobre una base SINTÉTICA
(`test/support_rdm2/c_seed.dart` para las pantallas y
`tool/rediseno/pdf_rdm2_c_test.dart` para los PDF). No hay datos reales.

| Carpeta | Código | Cómo se generó |
|---|---|---|
| `antes/` | base `77deb95` (se restauró `lib/` de la base sólo para la ejecución y se devolvió a HEAD) | `RDM_SHOTS=… RDM_TEXT_SCALE=<1.0\|1.3\|2.0> RDM_WIDTH=<390\|900> flutter test tool/rediseno/capturas_rdm2_c_test.dart` |
| `despues/` | `ef01e72` | el mismo comando |
| `pdf/antes/` | base `77deb95` | `RDM_PDF_OUT=… flutter test tool/rediseno/pdf_rdm2_c_test.dart` y `python -E -P tool/rediseno/render_pdf_rdm2_c.py <carpeta>` (PyMuPDF) |
| `pdf/despues/` | `b239afc` | el mismo procedimiento |

Sufijos: sin sufijo = 390 dp y letra 1,0; `_x13` / `_x20` = letra 1,3 / 2,0;
`_w900` = 900 dp de ancho.

Salida de PyMuPDF (páginas, hoja y «…» en el texto extraído):

- antes: `estado_cuenta_todas.pdf` 2 páginas, 595×842 pt, 209 «…»;
  `estado_cuenta_invierno.pdf` 2, 595×842, 210; `movimientos_propios_todas.pdf`
  1, 595×842, 30.
- después: `estado_cuenta_todas.pdf` 4 páginas, 842×595 pt, 0 «…»;
  `estado_cuenta_invierno.pdf` 5, 842×595, 0; `movimientos_propios_todas.pdf`
  2, 595×842, 0.

Las páginas en PNG se miraron una a una; que PyMuPDF lea el archivo no
demuestra por sí solo que se vea bien.
