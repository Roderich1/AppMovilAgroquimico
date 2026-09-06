# Compila `libwhisper_bench.so` para el banco de pruebas.
#
# Derivado del CMakeLists del ejemplo Android de whisper.cpp (MIT). No lo invoca
# Gradle: lo invoca `tool/build_whisper_libs.sh`, que clona whisper.cpp en el
# commit fijado y pasa su ruta en `WHISPER_SRC`. Así el APK se arma con
# librerías ya compiladas y verificables, y el spike se borra quitando la carpeta.

cmake_minimum_required(VERSION 3.10)
project(whisper_bench C CXX)

set(CMAKE_CXX_STANDARD 17)

if (NOT DEFINED WHISPER_SRC)
    message(FATAL_ERROR "Falta -DWHISPER_SRC=<ruta a whisper.cpp>")
endif ()
if (NOT DEFINED WHISPER_BENCH_VERSION)
    set(WHISPER_BENCH_VERSION "desconocida")
endif ()

# `whisper.cpp` referencia `WHISPER_VERSION` en tiempo de compilacion; upstream lo
# saca de su propio CMakeLists. Sin esto el build falla con "use of undeclared
# identifier 'WHISPER_VERSION'".
file(READ "${WHISPER_SRC}/CMakeLists.txt" _whisper_root_cmake)
string(REGEX MATCH "project\(\"whisper\.cpp\" VERSION ([0-9]+\.[0-9]+\.[0-9]+)\)"
        _unused "${_whisper_root_cmake}")
if (CMAKE_MATCH_1)
    set(WHISPER_UPSTREAM_VERSION ${CMAKE_MATCH_1})
else ()
    set(WHISPER_UPSTREAM_VERSION "0.0.0")
endif ()
message(STATUS "whisper.cpp version: ${WHISPER_UPSTREAM_VERSION}")

add_library(whisper_bench SHARED
        ${WHISPER_SRC}/src/whisper.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/whisper_jni.c
)

target_compile_definitions(whisper_bench PUBLIC GGML_USE_CPU)
target_compile_definitions(whisper_bench PRIVATE
        WHISPER_BENCH_VERSION="${WHISPER_BENCH_VERSION}"
        WHISPER_VERSION="${WHISPER_UPSTREAM_VERSION}")

target_include_directories(whisper_bench PRIVATE
        ${WHISPER_SRC}
        ${WHISPER_SRC}/src
        ${WHISPER_SRC}/include
        ${WHISPER_SRC}/ggml/include
        ${WHISPER_SRC}/ggml/src
        ${WHISPER_SRC}/ggml/src/ggml-cpu
)

if (NOT CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_options(whisper_bench PRIVATE -O3)
    target_compile_options(whisper_bench PRIVATE -fvisibility=hidden -fvisibility-inlines-hidden)
    target_compile_options(whisper_bench PRIVATE -ffunction-sections -fdata-sections)
    target_link_options(whisper_bench PRIVATE -Wl,--gc-sections)
endif ()

# OpenMP FUERA. Con el activado, `libggml-base.so` queda enlazada contra
# `libomp.so`, que el NDK no empaqueta en el APK: la carga falla en el telefono
# con `dlopen failed: library "libomp.so" not found`. ggml trae su propio pool de
# hilos, que es lo que usan las builds de Android de whisper.cpp.
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)

include(FetchContent)
FetchContent_Declare(ggml SOURCE_DIR ${WHISPER_SRC}/ggml)
FetchContent_MakeAvailable(ggml)

find_library(LOG_LIB log)
target_link_libraries(whisper_bench ${LOG_LIB} android ggml)
