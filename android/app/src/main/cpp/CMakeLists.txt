# `libagro_whisper.so`: whisper.cpp más el puente JNI de la segunda pasada.
#
# Derivado del CMakeLists del banco híbrido y del ejemplo Android de whisper.cpp
# (MIT). No lo invoca Gradle: lo invoca `tool/voice_local/build_whisper_libs.sh`,
# que obtiene whisper.cpp en el commit fijado y pasa su ruta en `WHISPER_SRC`.
# Sin esas librerías la app compila igual y la segunda pasada queda
# «no disponible»; Vosk sigue funcionando.

cmake_minimum_required(VERSION 3.10)
project(agro_whisper C CXX)
set(CMAKE_CXX_STANDARD 17)

if (NOT DEFINED WHISPER_SRC)
    message(FATAL_ERROR "Falta -DWHISPER_SRC=<ruta a whisper.cpp>")
endif ()

file(READ "${WHISPER_SRC}/CMakeLists.txt" _whisper_root_cmake)
string(REGEX MATCH "project\(\"whisper\.cpp\" VERSION ([0-9]+\.[0-9]+\.[0-9]+)\)"
        _unused "${_whisper_root_cmake}")
set(WHISPER_UPSTREAM_VERSION ${CMAKE_MATCH_1})

add_library(agro_whisper SHARED
        ${WHISPER_SRC}/src/whisper.cpp
        ${CMAKE_CURRENT_SOURCE_DIR}/whisper_jni.c)
target_compile_definitions(agro_whisper PUBLIC GGML_USE_CPU)
target_compile_definitions(agro_whisper PRIVATE WHISPER_VERSION="${WHISPER_UPSTREAM_VERSION}")
target_include_directories(agro_whisper PRIVATE
        ${WHISPER_SRC} ${WHISPER_SRC}/src ${WHISPER_SRC}/include
        ${WHISPER_SRC}/ggml/include ${WHISPER_SRC}/ggml/src ${WHISPER_SRC}/ggml/src/ggml-cpu)
target_compile_options(agro_whisper PRIVATE -O3 -fvisibility=hidden
        -fvisibility-inlines-hidden -ffunction-sections -fdata-sections)
target_link_options(agro_whisper PRIVATE -Wl,--gc-sections -Wl,-z,max-page-size=16384)

# Sin OpenMP: el NDK no empaqueta `libomp.so` y la carga fallaría en el teléfono
# (hallazgo del banco). ggml usa su propio pool de hilos.
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
include(FetchContent)
FetchContent_Declare(ggml SOURCE_DIR ${WHISPER_SRC}/ggml)
FetchContent_MakeAvailable(ggml)

find_library(LOG_LIB log)
target_link_libraries(agro_whisper ${LOG_LIB} android ggml)
