# Fuentes de prueba

`roboto-regular.ttf`, `roboto-medium.ttf` y `roboto-bold.ttf` son **Roboto**, la fuente de Material en Android. Copyright 2011 Google Inc. Licencia Apache 2.0: texto íntegro en `LICENSE-Apache-2.0.txt`.

**Procedencia:** se copiaron sin modificar del artefacto `material_fonts` del SDK de Flutter 3.47.2 (`bin/cache/artifacts/material_fonts`) el 2026-10-17.

**Uso:** sólo en `test/f10_legibility_97_test.dart`, para medir con la fuente real del teléfono. La de prueba por defecto dibuja cada glifo como un cuadrado.

No se empaquetan en la aplicación: no están en `pubspec.yaml`.
