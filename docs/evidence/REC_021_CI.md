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
