# 32 — Línea base de estabilización

Estado del repositorio **antes** de cualquier modificación de esta fase de estabilización.
Todo lo registrado aquí se midió ejecutando los comandos, no leyendo documentación.

Fecha de captura: **2026-09-05**

## Control de versiones

| Dato | Valor |
|---|---|
| ¿Repositorio Git? | **Sí** |
| Rama actual | `hardening/stabilization` |
| Commit base (HEAD) | `5d0b8efb1d19f5f76ba3d9a7ee4e76d7dcb95ef6` |
| Mensaje del commit base | `proyecto base` |
| Historial | `5d0b8ef proyecto base` · `739293d first commit` |
| Ramas | `hardening/stabilization` (actual), `main`, `remotes/origin/main` |
| Estado del árbol de trabajo | **Limpio** (`git status --short` sin salida) |
| `docs/` bajo control de versiones | Sí — 32 archivos ya versionados |

> **Corrección de la auditoría anterior.** El documento
> [27_KNOWN_ISSUES](27_KNOWN_ISSUES.md) registró **KI-20: "el directorio de trabajo no está
> bajo control de versiones"**, porque en aquel momento `git rev-parse` fallaba. **Eso ya no
> es cierto**: el repositorio existe, tiene remoto (`origin/main`) y una rama de trabajo
> dedicada. KI-20 queda **YA CORREGIDO** y se actualiza en su documento.

## Toolchain

| Componente | Versión |
|---|---|
| Flutter | **3.47.2** · canal `stable` |
| Framework revision | `d3b14c8769` (2026-08-26) |
| Engine | `1cf1c4773fb941c4c74a7f8bb144a8837596c0f4` (rev `a804b26164`) |
| Dart | **3.13.2** |
| DevTools | 2.60.0 |

## Resultados de los comandos de verificación

### `flutter pub get`

```
Got dependencies!
15 packages have newer versions incompatible with dependency constraints.
```

✅ Sin errores. Los 15 paquetes con versiones más nuevas están bloqueados por restricciones
de dependencias transitivas; ninguno es una dependencia directa del proyecto. No se actualiza
nada (ver Fase 14 del plan: no actualizar en masa sin necesidad concreta).

### `flutter analyze`

```
Analyzing AppFamiliaAgricultor...
No issues found! (ran in 1.1s)
```

✅ **0 errores, 0 warnings, 0 lints.**

### `dart format --output=none --set-exit-if-changed lib test`

```
Formatted 39 files (0 changed) in 0.24 seconds.
```

✅ **0 archivos requerirían reformateo.**

### `dart format --output=none --set-exit-if-changed .` (repositorio completo)

❌ **Falla, pero NO por el código del proyecto.**

```
PathNotFoundException: Directory listing failed, path =
'.\build\flutter_plugin_android_lifecycle\.transforms\...\bundleLibRuntimeToDirDebug_dex\
io\flutter\embedding\engine\plugins\lifecycle\*'
(OS Error: El sistema no puede encontrar la ruta especificada, errno = 3)
#2  _processDirectory (package:dart_style/src/io.dart:144)
```

**Diagnóstico**: `dart format .` recorre `build/`, que contiene directorios de transformación
de Gradle con rutas muy profundas. En Windows esto supera el límite de ruta y el recorrido
del directorio falla. **No hay ningún archivo Dart mal formateado.**

`build/` está correctamente en `.gitignore`, pero `dart format` no lee `.gitignore`.

**Conclusión**: el comando correcto para este proyecto es el que ya documenta el `README.md`:
`dart format --output=none --set-exit-if-changed lib test`. Se registra como hallazgo
**STAB-018** (P3) por su impacto en una futura configuración de CI.

### `flutter test`

```
00:13 +44: All tests passed!
```

✅ **44 tests, 44 pasados, 0 fallidos, 0 saltados.** Duración ~13 s.

Desglose por archivo (13 archivos):

| Archivo | Tests |
|---|---:|
| `repository_test.dart` | 11 |
| `v5_domain_test.dart` | 6 |
| `v4_repository_test.dart` | 4 |
| `regression_widget_test.dart` | 4 |
| `money_test.dart` | 3 |
| `adaptive_picker_test.dart` | 2 |
| `back_navigation_test.dart` | 2 |
| `migration_test.dart` | 2 |
| `widget_test.dart` | 2 |
| `e2e_scenario_test.dart` | 1 |
| `e2e_v5_test.dart` | 1 |
| `responsive_v5_test.dart` | 1 (×5 tamaños) |
| `volume_test.dart` | 1 |

## Métricas de código

| Métrica | Valor |
|---|---:|
| Líneas Dart en `lib/` | 8 250 |
| Líneas Dart en `test/` | 1 972 |
| Archivos Dart totales | 39 |
| Pantallas | 17 |
| Rutas `GoRoute` | 17 |
| Tablas SQLite | 22 |
| Índices SQLite | 15 |
| Versión de esquema | 4 |

## Build de release

**No ejecutada en la línea base.** Se ejecuta en la Fase 11 (Release Readiness) para no
atribuir posteriormente a los cambios de estabilización un fallo preexistente. El resultado
se registra en [35_RELEASE_READINESS](35_RELEASE_READINESS.md).

## Compromiso de no atribución

Todo problema documentado en esta página **existía antes** de la estabilización. Ningún
fallo listado aquí se atribuirá a los cambios realizados en esta fase.

Inversamente: cualquier regresión que aparezca después de esta captura **sí** es atribuible
al trabajo de estabilización y debe corregirse antes de cerrar.

## Criterio de no regresión

Al cerrar la estabilización, estos cuatro comandos deben seguir dando el mismo resultado o
mejor:

| Comando | Línea base | Requisito al cerrar |
|---|---|---|
| `flutter analyze` | 0 issues | **0 issues** |
| `dart format ... lib test` | 0 changed | **0 changed** |
| `flutter test` | 44/44 | **≥ 44 tests, 0 fallidos** |
| `flutter build apk --release` | No medida | Medida y documentada |
