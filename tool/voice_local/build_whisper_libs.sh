#!/usr/bin/env bash
# Compila `libagro_whisper.so` (whisper.cpp + puente JNI) para el APK.
#
#   bash tool/voice_local/build_whisper_libs.sh [abi ...]   # por defecto arm64-v8a x86_64
#
# Deja las `.so` en `android/app/src/main/jniLibs/<abi>/` (ignorado por git).
# whisper.cpp se obtiene en el commit FIJADO del banco híbrido
# (52a939a2a762224e255d366c1182b2af4dd1a032) y el tar se verifica por SHA-256.
#
# x86_64 es sólo para el emulador: se compila con AVX2/FMA/F16C porque, sin
# ellas, ggml cae a SSE y en el emulador una frase de 3 s tardó 45 s en el banco.
# Una CPU x86_64 sin AVX2 no podría ejecutar esa variante; arm64 usa la base
# armv8-a sin extensiones, que corre en cualquier teléfono de 64 bits.
set -euo pipefail

COMMIT=52a939a2a762224e255d366c1182b2af4dd1a032
TAR_SHA=6212572f00e887698440dbbf87aef27de6e56dbe73907f6148686ec55d584a19
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
CACHE="${AGRO_VOICE_CACHE:-${LOCALAPPDATA:-$HOME/.cache}/AgroVoiceModels/dl}"
command -v cygpath >/dev/null && CACHE=$(cygpath -u "$CACHE")
WORK="$CACHE/../whisper-android"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${LOCALAPPDATA:-$HOME}/Android/Sdk}}"
NDK="$SDK/ndk/${NDK_VERSION:-28.2.13676358}"
CMAKE_BIN="$SDK/cmake/3.22.1/bin/cmake"
NINJA_BIN="$SDK/cmake/3.22.1/bin/ninja"
ABIS=("$@"); [ ${#ABIS[@]} -eq 0 ] && ABIS=(arm64-v8a x86_64)

mkdir -p "$CACHE" "$WORK"
TAR="$CACHE/whisper.cpp-$COMMIT.tar.gz"
[ -f "$TAR" ] || curl -sSfL -o "$TAR" "https://codeload.github.com/ggml-org/whisper.cpp/tar.gz/$COMMIT"
[ "$(sha256sum < "$TAR" | awk '{print $1}')" = "$TAR_SHA" ] || { echo "SHA-256 del código de whisper.cpp NO coincide" >&2; exit 1; }
SRC="$WORK/whisper.cpp-$COMMIT"
[ -d "$SRC" ] || tar xzf "$TAR" -C "$WORK"

STRIP=$(ls "$NDK"/toolchains/llvm/prebuilt/*/bin/llvm-strip* | head -1)
for ABI in "${ABIS[@]}"; do
  BUILD="$WORK/build-$ABI"
  extra=()
  [ "$ABI" = x86_64 ] && extra=(-DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON)
  rm -rf "$BUILD"
  "$CMAKE_BIN" -S "$HERE/android/app/src/main/cpp" -B "$BUILD" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$NINJA_BIN" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" -DANDROID_PLATFORM=android-24 \
    -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=OFF "${extra[@]}" \
    -DWHISPER_SRC="$SRC" > "$BUILD.log" 2>&1 || { tail -20 "$BUILD.log"; exit 1; }
  "$CMAKE_BIN" --build "$BUILD" -j 8 >> "$BUILD.log" 2>&1 || { tail -30 "$BUILD.log"; exit 1; }
  OUT="$HERE/android/app/src/main/jniLibs/$ABI"
  rm -rf "$OUT"; mkdir -p "$OUT"
  cp "$BUILD/libagro_whisper.so" "$BUILD"/_deps/ggml-build/src/libggml*.so "$OUT/"
  "$STRIP" --strip-unneeded "$OUT"/*.so
  echo "== $ABI =="; ls -l "$OUT" | awk 'NR>1{print $5, $9}'
done
echo "whisper.cpp $COMMIT"
