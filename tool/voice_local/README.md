# Voz local de Agrocuentas: probar y recompilar

## Demostración en el emulador

**Versión de demostración** (ADR-005, aceptada provisionalmente): la APK `agrocuentas-voz-03124a0-x86_64-profile.apk`, ya instalada y activada en el emulador `Pixel_8` como **«AC VOZ»** (`com.comunidad.agro.agroquimicos.voz`). Tiene la cuenta sintética `agricultor6` de la DEMO y siete productos en el catálogo. No hace falta reinstalarla.

1. **Arrancar el emulador**, si no está abierto:
   ```bash
   "$LOCALAPPDATA/Android/Sdk/emulator/emulator" -avd Pixel_8 -no-snapshot-save
   ```
2. **Habilitar el micrófono.**
   1. En la barra del emulador, abre **⋯ (Extended controls)**, entra en **Microphone** y activa **«Virtual microphone uses host audio input»**.
   2. Si no llega la voz, en Windows revisa **Configuración › Privacidad › Micrófono › «Permitir que las aplicaciones de escritorio accedan al micrófono»**.
   3. Al cerrar el emulador, el ajuste se pierde: hay que activarlo de nuevo en cada arranque.
3. **Quitar la red.** Activa el modo avión en los ajustes rápidos del emulador. El dictado no usa la red, y la pantalla lo confirma con «Funciona sin conexión».
4. **Abrir el dictado.** En **AC VOZ**, ve a **Operaciones › Más › Registrar por voz** y elige **Compra por voz**, **Planificación por voz** o **Aplicación por voz**.
5. **Dictar.**
   1. Toca **Hablar**. La primera vez, Android pide el permiso de micrófono.
   2. Habla con normalidad, por ejemplo: «compré dos litros de glifosato a ciento veinte bolivianos», una pausa, y «compré cinco kilos de mancozeb».
   3. El texto provisional aparece en cursiva. Al hacer una pausa, la frase pasa a «revisando» y luego al borrador.
6. **Detener.** Toca **Detener** y revisa el borrador. Nada se registra hasta que pulses el botón de registrar.
7. **Repetir.** Descarta el borrador y vuelve a **Hablar**: no arrastra texto del intento anterior.

**Para terminar:**
- desactiva «Virtual microphone uses host audio input»;
- quita el modo avión.

**Ten en cuenta:**
- **Silencio.** Tras 30 s sin voz, el dictado se cierra solo.
- **El emulador no es un teléfono.** Sus tiempos, y el audio que recibe del PC, no son los de un teléfono.
- **Tus observaciones** van en `docs/evidence/F09_VOZ_LOCAL_OBSERVACIONES_AUTOR.md`, aparte de los resultados sintéticos.

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
