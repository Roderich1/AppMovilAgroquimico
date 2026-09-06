# ADR-001 — Generar el PDF sin la dependencia `pdf`

| Campo | Valor |
|---|---|
| Estado | `Accepted` |
| Fecha | 2026-09-06 |
| Alcance | `EVO-006` (EVOLUTION-2) |
| Rama | `evolution/evolution-2-typed-reports` |
| Reemplaza a | — |

## Contexto

`features/EVOLUTION-2_TYPED_READS_AND_REPORT_EXPORT_SPEC.md` propone
[`pdf`](https://pub.dev/packages/pdf) `^3.13.0` **como candidato**, no como decisión cerrada, y
exige textualmente: *"Ejecutar `flutter pub get` y comprobar compatibilidad real antes de cerrar
la selección"*.

La comprobación se hizo sobre el toolchain fijado (Flutter 3.47.2 / Dart 3.13.2) y **falla**:

```text
$ flutter pub add 'pdf:^3.13.0' --dry-run
Because pdf >=3.11.2 depends on archive >=3.4.0 <4.1.0 and agroquimicos depends on
archive ^4.2.0, pdf >=3.11.2 is forbidden.
So, because agroquimicos depends on pdf 3.13.0, version solving failed.
```

Se probaron además `3.11.3`, `3.11.1`, `3.10.8` y `4.0.0`. Ninguna versión publicada de `pdf`
admite `archive ^4.2.0`, y no existe una serie 4.x del paquete.

`archive` no es una dependencia accesoria: es la librería con la que `BackupService` construye
y lee el contenedor `.agrobackup`, el formato de respaldo 1 descrito en
`docs/46_BASELINE_FINAL_FREEZE.md` §9.

## Decisión

**No se añade `pdf`.** El PDF se genera con un escritor propio en Dart puro,
`lib/services/reports/pdf_writer.dart`, sin ninguna dependencia nueva.

## Alternativas consideradas

### A. Degradar `archive` a `>=4.0.0 <4.1.0`

Resuelve, y se verificó que resuelve:

```text
$ # con archive ">=4.0.0 <4.1.0"
$ flutter pub add 'pdf:^3.13.0' --dry-run
Would change 9 dependencies.
```

**Rechazada.** Cambia la librería que implementa el formato de respaldo, que EVOLUTION-2 tiene
explícitamente prohibido tocar, y lo haría para una funcionalidad de conveniencia. El respaldo
es la única vía de recuperación del usuario: arriesgarlo para no escribir un generador de PDF
es un intercambio malo. Además arrastraría nueve paquetes nuevos (`image`, `bidi`, `barcode`,
`qr`, `xml`, `petitparser`, `path_parsing`, `vector_math`, `pdf`), ampliando la superficie de
mantenimiento de una aplicación que hoy tiene once dependencias directas.

### B. Aplazar `EVO-006`

**Rechazada.** El requisito de producto es un reporte imprimible; la elección de librería es un
medio, no el fin. La especificación pide un formato (A4 multipágina, cabeceras, totales,
español), no un paquete concreto.

### C. Escritor propio

**Aceptada.** PDF 1.4 con las fuentes estándar Helvetica y Helvetica-Bold en
`WinAnsiEncoding`, que cubre el español completo sin incrustar tipografías. Incluye las
métricas AFM de ambas fuentes para alinear a la derecha y recortar por ancho real.

## Consecuencias

**A favor**

- Cero dependencias nuevas; `archive` y el respaldo quedan intactos.
- Control directo de la codificación, que es justo lo que exige `EVO-006-REQ-003` para la `ñ`
  y las tildes.
- Los flujos van sin comprimir, así que los tests comprueban lo que el archivo dice de verdad
  y no sólo que pesa algo.

**En contra**

- Código propio que mantener (~810 líneas, de las que ~450 son las dos tablas de métricas).
- No hay imágenes, ni fuentes incrustadas, ni gráficos: sólo tablas de texto. Es lo que los
  cinco reportes necesitan; cualquier ampliación exigiría revisar esta decisión.
- Los archivos son mayores que si fueran comprimidos. Un reporte de 200 filas ronda los 60 KB,
  irrelevante en un teléfono.

## Seguridad y datos

No cambia nada: el PDF se genera en memoria a partir del modelo tabular neutral, no consulta
SQLite y no toca el sistema de archivos. El almacenamiento es una frontera aparte que no conoce
el contenido. Ninguna red, ningún permiso nuevo.

## Compatibilidad

No afecta al esquema `6`, ni al formato de respaldo `1`, ni a `pubspec.yaml`, que no cambia.

## Rollback

Retirar `lib/services/reports/pdf_*.dart` y la opción PDF de la pantalla. El CSV y las lecturas
tipadas no dependen de esta decisión.

## Evidencia

- Resolución fallida y resolución alternativa, reproducidas arriba.
- `pubspec.yaml` y `pubspec.lock` sin cambios respecto de
  `44c2e792aa3d96a601428777a3a0419568a77ac1`.
- `test/report_pdf_test.dart`: 24 tests de estructura, tabla `xref` coherente, paginación,
  cabeceras repetidas, español en WinAnsi, nombres largos, importes de diez cifras, paréntesis
  escapados y equivalencia de valores con el CSV.

## Revisión

Si en el futuro `pdf` publica una versión compatible con `archive ^4.x`, conviene reevaluar:
esta decisión resuelve un conflicto concreto, no afirma que un escritor propio sea mejor que
una librería madura.
