#!/usr/bin/env bash
# Descarga los modelos Whisper del banco de pruebas y VERIFICA su SHA-256.
#
# HERRAMIENTA DE SPIKE. No la usa la aplicación Agrocuentas ni su CI.
#
#   bash tool/fetch_whisper_models.sh
#
# Los deja donde Gradle los empaqueta como assets del sabor correspondiente:
#   android/app/src/whisperTiny/assets/models/ggml-tiny-q5_1.bin
#   android/app/src/whisperBase/assets/models/ggml-base-q5_1.bin
#
# El hash NO es decorativo: un modelo distinto es otro candidato y mediría otra
# cosa. Si no coincide, el script falla y borra el archivo.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BASE_URL=https://huggingface.co/ggerganov/whisper.cpp/resolve/main

# nombre|sabor|sha256
MODELS=(
  "ggml-tiny-q5_1.bin|whisperTiny|818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7"
  "ggml-base-q5_1.bin|whisperBase|422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898"
)

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

for entry in "${MODELS[@]}"; do
  IFS='|' read -r NAME FLAVOR EXPECTED <<<"$entry"
  DEST_DIR="$HERE/android/app/src/$FLAVOR/assets/models"
  DEST="$DEST_DIR/$NAME"
  mkdir -p "$DEST_DIR"

  if [ -f "$DEST" ] && [ "$(sha256_of "$DEST")" = "$EXPECTED" ]; then
    echo "ok (ya presente): $NAME"
    continue
  fi

  echo "descargando $NAME ..."
  curl -sSL -o "$DEST" "$BASE_URL/$NAME"

  ACTUAL="$(sha256_of "$DEST")"
  if [ "$ACTUAL" != "$EXPECTED" ]; then
    rm -f "$DEST"
    echo "SHA-256 NO COINCIDE para $NAME" >&2
    echo "  esperado: $EXPECTED" >&2
    echo "  obtenido: $ACTUAL" >&2
    exit 1
  fi
  echo "ok: $NAME  ($(wc -c <"$DEST") bytes)  sha256=$ACTUAL"
done

echo
echo "Modelos listos. Licencia: MIT (OpenAI Whisper); conversion ggml por whisper.cpp (MIT)."
