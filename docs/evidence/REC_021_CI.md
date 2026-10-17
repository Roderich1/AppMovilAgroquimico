# Evidencia — REC-021 (#57): CI de regresión en cada push

- Fecha de verificación: 2026-10-15
- Commit verificado: `278cbd32dc59b26824f59fcefb77bebbc3cecb95` (`origin/main`)
- Workflow: `.github/workflows/flutter-ci.yml` («Flutter CI»), disparadores `push` a `main`, `pull_request` y `workflow_dispatch`; Flutter fijado en 3.47.2.

## Pasos que ejecuta el CI

| Paso | Comando |
|---|---|
| Formato | `dart format --output=none --set-exit-if-changed lib test` |
| Análisis estático | `flutter analyze` |
| Tests | `flutter test` |
| Build de release (sin firmar) | `flutter build apk --release` |

## Ejecuciones consultadas (`gh run view`)

| Ejecución | Evento | Commit | Resultado | Fecha de la ejecución |
|---|---|---|---|---|
| [37231657078](https://github.com/Roderich1/AppMovilAgroquimico/actions/runs/37231657078) | push `main` | `278cbd3` | success (los 4 pasos en success) | 2026-10-04 |
| [38728787229](https://github.com/Roderich1/AppMovilAgroquimico/actions/runs/38728787229) | pull_request (`evidence/rec-mobile-baseline-2026-10-15`) | `5d57fcc` | success (los 4 pasos en success) | 2026-10-15 |

## Conclusión

El criterio del autor para `Verified` (el CI ejecuta `flutter analyze` y `flutter test` en cada push) se cumple: el workflow corre en cada push a `main` y en cada PR, y el último push a `main` terminó en success con análisis y tests verdes.

Mejora registrada para F10 (no bloquea): automatizar la comprobación de que el workflow conserva esos pasos y de que la versión fijada de Flutter coincide con la baseline.

Verificado el 2026-10-15 con Claude Code en el equipo del autor, consultando las ejecuciones anteriores. La verificación del autor (Roderich Rendón) queda registrada al aprobar el PR; la revisión del tutor se registra aparte en GOV-01.

## Nota añadida el 2026-10-17 (sesión A, tras la revisión de la sesión C)

No cambia lo registrado el 2026-10-15.

- **#57 sigue Partial** y este PR no la cierra. La conclusión de arriba sobre el CI se mantiene, pero `REC_MOBILE_BASELINE.md` da su cobertura de pruebas como «partial (tests)», y su sección de #57 deja pendientes: ninguna automatización comprueba el workflow; `docs/46` no registra el SHA del tag; y el tag `v1.0.0-base-stable` (`bd3289f`) no coincide con el merge `f4c6510` de #4, que no está en `main`.
- **La ejecución 38728787229** de la tabla corrió sobre `5d57fcc`, un commit que no está en ninguna rama. Su árbol es idéntico al de `0ab6043`: es la versión anterior a la reescritura del historial que retiró las líneas de atribución.
- El CI de la cabeza de este PR es la ejecución 39042305677 (`bf9b93d`, success), y después la del HEAD final.

