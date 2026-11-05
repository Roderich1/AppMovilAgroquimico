# Voz local de Agrocuentas: probar y recompilar

## Probar el dictado en el emulador (5 minutos)

La app de prueba ya está instalada y activada en el emulador `Pixel_8`: es el paquete aislado **«AC VOZ»** (`com.comunidad.agro.agroquimicos.voz`), con la cuenta sintética de la DEMO `agricultor6` y siete productos en el catálogo.

1. **Arrancar el emulador.**
   ```bash
   "$LOCALAPPDATA/Android/Sdk/emulator/emulator" -avd Pixel_8 -no-snapshot-save
   ```
2. **Dar al emulador tu micrófono.** En la barra lateral del emulador, abre **⋯ (Extended controls)**, entra en **Microphone** y activa **«Virtual microphone uses host audio input»**. Esto lo haces tú: la sesión de preparación no lo activó nunca. Si el emulador lo desactiva al reiniciar, vuelve a activarlo.
3. **Sin Internet (opcional).** En el emulador, activa el modo avión desde los ajustes rápidos.
4. **Abrir el dictado.** Abre **AC VOZ** y ve a **Operaciones › Más › Registrar por voz › Compra por voz**. También están Plan y Aplicación por voz.
5. **Dictar.**
   1. Toca **Hablar**. La primera vez, Android pide el permiso de micrófono.
   2. Habla con normalidad, por ejemplo: «compré dos litros de glifosato a ciento veinte bolivianos», una pausa, y «compré cinco kilos de mancozeb».
   3. Mientras hablas aparece el texto provisional en cursiva. Al hacer una pausa, la frase pasa a «revisando» y después al borrador.
6. **Detener.** Toca **Detener**. Lo pendiente se procesa y queda para revisar. Nada se registra hasta que pulses «Registrar compra».

**Más cosas que puedes probar:**
- desactivar «Revisar cada frase» para comparar con sólo Vosk;
- descartar sin aplicar;
- salir de la pantalla mientras escucha;
- corregir un campo a mano y seguir dictando.

**Ten en cuenta:**
- **El emulador no es un teléfono.** Sus tiempos, y la calidad del audio que recibe del PC, no son los del teléfono.
- **Silencio.** Tras 30 s sin voz, el dictado se cierra solo y suelta el micrófono.

## Recompilar

```bash
bash tool/voice_local/fetch_voice_models.sh base        # o: small | none
bash tool/voice_local/build_whisper_libs.sh             # arm64-v8a y x86_64
bash tool/voice_local/build_voice_apk.sh x64   <carpeta>  # emulador
bash tool/voice_local/build_voice_apk.sh arm64 <carpeta>  # teléfono, sin instalar
```

- **Activar una instalación nueva.** Hace falta el Central. Exporta `AGRO_API_BASE_URL` con un origen HTTPS (por ejemplo, el túnel de la DEMO) antes de `build_voice_apk.sh`. El dictado en sí no usa la red.
- **Sin modelos ni librerías.** La app compila igual, y la pantalla de voz dice que el modelo no está instalado.

## Comprobaciones

- **Comparación HOST:** `synth_reference_audio.ps1` (audio sintético) y `host_compare.py`.
- **Inferencia real en el emulador:** `run_reference_check.sh <wav> <salida>`, que ejecuta `LocalVoiceEngineReferenceTest`.
- **La regla de la app sobre esos resultados:** `selection_on_results_test.dart`.

Procedencia, licencias y hashes: `THIRD_PARTY.md`. Resultados: `docs/evidence/F09_VOZ_LOCAL_2026-11-05.md`.
