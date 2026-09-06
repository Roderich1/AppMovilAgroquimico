#!/usr/bin/env bash
# Compila las librerías nativas de whisper.cpp para el banco de pruebas.
#
# HERRAMIENTA DE SPIKE. No la usa la aplicación Agrocuentas ni su CI.
#
#   bash tool/build_whisper_libs.sh [abi ...]      # por defecto arm64-v8a
#
# Deja los `.so` ya despojados de símbolos en:
#   android/app/src/whisperCommon/jniLibs/<abi>/
#
# Esas librerías NO se versionan (ver .gitignore): son producto de este script,
# que fija el commit de whisper.cpp para que el resultado sea reproducible.
set -euo pipefail

# whisper.cpp en un commit FIJO. Cambiarlo obliga a rehacer las mediciones: una
# versión distinta del motor es otro candidato, no el mismo.
WHISPER_COMMIT=52a939a2a762224e255d366c1182b2af4dd1a032
WHISPER_REPO=https://github.com/ggml-org/whisper.cpp.git

HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WHISPER_WORKDIR:-$HERE/build/whisper-src}"
OUT="$HERE/android/app/src/whisperCommon/jniLibs"
CPP="$HERE/android/app/src/whisperCommon/cpp"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${LOCALAPPDATA:-$HOME}/Android/Sdk}}"
NDK_VERSION="${NDK_VERSION:-28.2.13676358}"
NDK="$SDK/ndk/$NDK_VERSION"
CMAKE_BIN="$SDK/cmake/3.22.1/bin/cmake"
NINJA_BIN="$SDK/cmake/3.22.1/bin/ninja"
[ -x "$CMAKE_BIN" ] || [ -x "$CMAKE_BIN.exe" ] || CMAKE_BIN=cmake
[ -x "$NINJA_BIN" ] || [ -x "$NINJA_BIN.exe" ] || NINJA_BIN=ninja

ABIS=("$@")
[ ${#ABIS[@]} -eq 0 ] && ABIS=(arm64-v8a)

if [ ! -d "$NDK" ]; then
  echo "No existe el NDK $NDK_VERSION en $SDK/ndk" >&2
  exit 1
fi

# ------------------------------------------------------------------ obtener
if [ ! -d "$WORK/.git" ]; then
  mkdir -p "$(dirname "$WORK")"
  # `core.longpaths` es obligatorio en Windows: el repo trae rutas de ejemplo
  # más largas que MAX_PATH y el checkout falla sin esto.
  git -c core.longpaths=true clone --filter=blob:none --sparse "$WHISPER_REPO" "$WORK"
  git -C "$WORK" -c core.longpaths=true sparse-checkout set --skip-checks \
    src include ggml cmake
fi
git -C "$WORK" -c core.longpaths=true fetch --depth 1 origin "$WHISPER_COMMIT"
git -C "$WORK" -c core.longpaths=true checkout --detach "$WHISPER_COMMIT"

STRIP="$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe"
[ -x "$STRIP" ] || STRIP="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip"
[ -x "$STRIP" ] || STRIP="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-strip"

# ------------------------------------------------------------------ compilar
for ABI in "${ABIS[@]}"; do
  BUILD="$HERE/build/whisper-$ABI"
  rm -rf "$BUILD"
  "$CMAKE_BIN" -S "$CPP" -B "$BUILD" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$NINJA_BIN" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" \
    -DANDROID_PLATFORM=android-24 \
    -DCMAKE_BUILD_TYPE=Release \
    -DWHISPER_SRC="$WORK" \
    -DWHISPER_BENCH_VERSION="$WHISPER_COMMIT"
  "$CMAKE_BIN" --build "$BUILD" -j 8

  mkdir -p "$OUT/$ABI"
  cp "$BUILD/libwhisper_bench.so" "$OUT/$ABI/"
  cp "$BUILD"/_deps/ggml-build/src/libggml*.so "$OUT/$ABI/"
  "$STRIP" --strip-unneeded "$OUT/$ABI"/*.so
  echo "== $ABI =="
  ls -l "$OUT/$ABI"
done

echo
echo "whisper.cpp commit: $WHISPER_COMMIT"
echo "librerias en: $OUT"
