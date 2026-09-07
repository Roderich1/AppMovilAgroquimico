#!/usr/bin/env bash
# Descarga el modelo español de Vosk del banco de pruebas y VERIFICA su SHA-256.
#
# HERRAMIENTA DE SPIKE. No la usa la aplicación Agrocuentas ni su CI.
#
#   bash tool/fetch_vosk_model.sh
#
# Lo deja descomprimido donde Gradle lo empaqueta como asset de los sabores que
# lo miden:
#   android/app/src/vosk/assets/models/vosk-model-small-es-0.42/
#   android/app/src/hybrid/assets/models/vosk-model-small-es-0.42/
#
# El hash NO es decorativo: otro modelo es otro candidato y mediría otra cosa.
# Si no coincide, el script falla y borra la descarga.
#
# Procedencia verificada en fuente primaria el 2026-09-07 y registrada en
# THIRD_PARTY.md. **No existe un modelo español de Vosk de 180 MB**: la lista
# oficial sólo publica éste, de 39 MB, y uno de 1,4 GB orientado a servidor.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"

NAME=vosk-model-small-es-0.42
URL="https://alphacephei.com/vosk/models/$NAME.zip"
EXPECTED_SHA=09b239888f633ef2f0b4e09736e3d9936acfd810bc65d53fad45261762c6511f
EXPECTED_BYTES=39817833
# Tamaño ya descomprimido, para detectar una extracción a medias.
EXPECTED_INSTALLED_BYTES=60286598

FLAVORS=(vosk hybrid)

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

STAGE="$HERE/.vosk-stage"
mkdir -p "$STAGE"
ZIP="$STAGE/$NAME.zip"

if [ -f "$ZIP" ] && [ "$(sha256_of "$ZIP")" = "$EXPECTED_SHA" ]; then
  echo "ok (ya descargado): $NAME.zip"
else
  echo "descargando $NAME.zip ..."
  curl -sSL -o "$ZIP" "$URL"

  ACTUAL_SHA="$(sha256_of "$ZIP")"
  ACTUAL_BYTES="$(wc -c <"$ZIP")"
  if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ] || [ "$ACTUAL_BYTES" != "$EXPECTED_BYTES" ]; then
    rm -f "$ZIP"
    echo "EL MODELO NO ES EL REGISTRADO" >&2
    echo "  esperado: $EXPECTED_BYTES B  sha256=$EXPECTED_SHA" >&2
    echo "  obtenido: $ACTUAL_BYTES B  sha256=$ACTUAL_SHA" >&2
    exit 1
  fi
  echo "ok: $NAME.zip  ($ACTUAL_BYTES B)  sha256=$ACTUAL_SHA"
fi

# Se extrae UNA vez y se copia a cada sabor: descomprimir dos veces sería la
# mitad del tiempo del script sin ninguna ganancia.
EXTRACTED="$STAGE/$NAME"
if [ ! -d "$EXTRACTED/am" ]; then
  rm -rf "$EXTRACTED"
  unzip -q -o "$ZIP" -d "$STAGE"
fi

INSTALLED_BYTES="$(du -sb "$EXTRACTED" | cut -f1)"
if [ "$INSTALLED_BYTES" != "$EXPECTED_INSTALLED_BYTES" ]; then
  echo "LA EXTRACCION NO COINCIDE" >&2
  echo "  esperado: $EXPECTED_INSTALLED_BYTES B" >&2
  echo "  obtenido: $INSTALLED_BYTES B" >&2
  echo "  Un modelo a medias no falla al abrirse: da resultados inexplicables." >&2
  exit 1
fi

for FLAVOR in "${FLAVORS[@]}"; do
  DEST_DIR="$HERE/android/app/src/$FLAVOR/assets/models"
  mkdir -p "$DEST_DIR"
  rm -rf "${DEST_DIR:?}/$NAME"
  cp -r "$EXTRACTED" "$DEST_DIR/$NAME"
  echo "instalado en el sabor $FLAVOR: $DEST_DIR/$NAME"
done

echo
echo "Modelo listo. Licencia: Apache 2.0 (Alpha Cephei)."
echo "WER declarada: 16,02 (cv test) · 16,72 (mtedx test) · 11,21 (mls)."
