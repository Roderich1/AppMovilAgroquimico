# Release y versionado

## Tags

`v1.0.0-base-stable` es inmutable. Ninguna evolución lo mueve. Cada release posterior recibe
un tag nuevo sobre un commit que haya pasado gates.

## Política práctica

- Patch (`1.0.x`): corrección compatible sin capacidad nueva ni schema incompatible.
- Minor (`1.x.0`): capacidad compatible; puede incluir migración forward compatible.
- Major (`x.0.0`): cambio de contrato que requiere transición explícita.
- `versionCode`/build number siempre aumenta para distribución Android.

SemVer describe el producto; `schemaVersion` y `backupFormatVersion` evolucionan de manera
independiente y se registran en la release.

## Gates de release

1. Spec/traceability/DoD completas.
2. Format, analyze, tests y build en CI sobre el SHA exacto.
3. Migraciones y backup verificados si aplican.
4. Device verification para comportamiento móvil.
5. Riesgos residuales aceptados y release notes.
6. Artefacto firmado sólo con keystore custodiado, nunca versionado.

## Canales sugeridos

- Desarrollo: ramas cortas + PR.
- Candidate: build identificable para verificación.
- Stable: tag nuevo tras cierre.

No publicar desde una rama ni marcar stable por la existencia de un APK local.

## Compatibilidad declarada por release

Registrar: app/versionCode, schema, backup format, versiones de backup legibles, plataforma
verificada, SHA, CI run y migraciones incluidas.
