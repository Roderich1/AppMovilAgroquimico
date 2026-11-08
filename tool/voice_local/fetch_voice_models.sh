#!/usr/bin/env bash
# Deja los modelos de voz local listos para empaquetar en el APK.
#
#   bash tool/voice_local/fetch_voice_models.sh [base|small|none]
#
#   base  (por defecto) Vosk small-es 0.42 + Whisper base q5_1 (segunda pasada)
#   small               Vosk small-es 0.42 + Whisper small q5_1
#   none                sólo Vosk, sin segunda pasada
#
# Es la ÚNICA forma de elegir el modelo de revisión: la app lee el manifiesto
# (nombre y variante) y no cambia de modelo por su cuenta. El valor por defecto
# sigue siendo base (ADR-005, provisional); small es una opción de compilación
# para medir (#166). Para volver a base basta con ejecutar el script sin
# argumento.
#
# Descarga desde las fuentes oficiales SÓLO durante la preparación, verifica el
# SHA-256 fijado (el mismo que registró el banco híbrido el 2026-09-07) y escribe
# en `android/app/voice-models/voice/` (ignorado por git) los archivos y un
# `manifest.json` con el tamaño y el SHA-256 de cada uno. La app verifica cada
# archivo contra ese manifiesto al copiarlo; nunca descarga nada.
set -euo pipefail

REVIEW=${1:-base}
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE="${AGRO_VOICE_CACHE:-${LOCALAPPDATA:-$HOME/.cache}/AgroVoiceModels/dl}"
command -v cygpath >/dev/null && CACHE=$(cygpath -u "$CACHE")
OUT="$HERE/android/app/voice-models/voice"
mkdir -p "$CACHE"

VOSK=vosk-model-small-es-0.42
VOSK_URL=https://alphacephei.com/vosk/models/$VOSK.zip
VOSK_SHA=09b239888f633ef2f0b4e09736e3d9936acfd810bc65d53fad45261762c6511f
declare -A WHISPER_SHA=(
  [base]=422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898
  [small]=ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb
)

fetch() { # archivo url sha
  local file="$CACHE/$1"
  if [ ! -f "$file" ]; then
    echo "descargando $2"
    curl -sSfL -o "$file.part" "$2" && mv "$file.part" "$file"
  fi
  local got
  got=$(sha256sum < "$file" | awk '{print $1}')
  if [ "$got" != "$3" ]; then
    echo "SHA-256 NO coincide para $1: esperado $3, obtenido $got" >&2
    rm -f "$file"
    exit 1
  fi
  echo "verificado $1 $got"
}

fetch "$VOSK.zip" "$VOSK_URL" "$VOSK_SHA"
case "$REVIEW" in
  base|small)
    GGML=ggml-$REVIEW-q5_1.bin
    fetch "$GGML" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$GGML" "${WHISPER_SHA[$REVIEW]}" ;;
  none) GGML= ;;
  *) echo "uso: $0 [base|small|none]" >&2; exit 2 ;;
esac

rm -rf "$OUT"
mkdir -p "$OUT"
python -I - "$CACHE" "$OUT" "$VOSK" "$GGML" "$REVIEW" <<'PY'
import hashlib, json, pathlib, shutil, sys, zipfile
cache, out, vosk, ggml, review = sys.argv[1:6]
cache, out = pathlib.Path(cache), pathlib.Path(out)

def describe(root):
    files = {}
    for f in sorted(p for p in root.rglob('*') if p.is_file()):
        files[f.relative_to(root).as_posix()] = {
            'size': f.stat().st_size,
            'sha256': hashlib.sha256(f.read_bytes()).hexdigest(),
        }
    return files

with zipfile.ZipFile(cache / f'{vosk}.zip') as z:
    for info in z.infolist():
        name = pathlib.PurePosixPath(info.filename)
        if info.is_dir() or name.parts[0] != vosk or '..' in name.parts:
            continue
        target = out / pathlib.Path(*name.parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(z.read(info))
manifest = {
    'vosk': {
        'name': vosk,
        'source': f'https://alphacephei.com/vosk/models/{vosk}.zip',
        'license': 'Apache-2.0',
        'files': describe(out / vosk),
    },
}
if ggml:
    folder = out / f'whisper-{review}-q5_1'
    folder.mkdir()
    shutil.copyfile(cache / ggml, folder / ggml)
    manifest['whisper'] = {
        'name': folder.name,
        # La app la informa en la disponibilidad y decide con ella si el
        # teléfono admite la segunda pasada (`ReviewCapabilityPolicy`).
        'variant': review,
        'file': ggml,
        'source': f'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/{ggml}',
        'license': 'MIT',
        'files': describe(folder),
    }
(out / 'manifest.json').write_text(json.dumps(manifest, indent=1), encoding='utf-8')
total = sum(f['size'] for e in manifest.values() for f in e['files'].values())
print(f'modelos listos en {out}: {total} B')
PY
