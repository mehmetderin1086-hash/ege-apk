# On-device OpenAI Whisper (whisper.cpp v1.9.5, MIT) for JARVIS.
# Models (ggml) are downloaded at runtime from Hugging Face.
cmake_minimum_required(VERSION 3.14)
project(jarvis_whisper C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(WHISPER_DIR ${CMAKE_CURRENT_SOURCE_DIR}/whisper.cpp)

# ggml: CPU backend only, linked statically, ggml's own thread pool.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GGML_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
if (ANDROID_ABI STREQUAL "arm64-v8a")
    # ARMv8.2 dot-product + fp16 (Cortex-A55/A75 and newer). Kotlin checks the
    # CPU flags before loading the library, so older CPUs never crash.
    set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+fp16" CACHE STRING "" FORCE)
endif ()

add_subdirectory(${WHISPER_DIR}/ggml ggml_build)

add_library(jarvis_whisper SHARED
    ${WHISPER_DIR}/src/whisper.cpp
    ${WHISPER_DIR}/src/aneforge/whisper-aneforge.cpp
    jarvis_whisper_jni.c
)

target_include_directories(jarvis_whisper PRIVATE
    ${WHISPER_DIR}/include
    ${WHISPER_DIR}/src
    ${WHISPER_DIR}/ggml/include
)
target_compile_definitions(jarvis_whisper PRIVATE WHISPER_VERSION="1.9.5")

if (NOT CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_options(jarvis_whisper PRIVATE -O3 -ffunction-sections -fdata-sections)
    target_link_options(jarvis_whisper PRIVATE -Wl,--gc-sections -Wl,--exclude-libs,ALL)
endif ()
if (ANDROID_ABI STREQUAL "arm64-v8a")
    target_compile_options(jarvis_whisper PRIVATE -march=armv8.2-a+dotprod+fp16)
endif ()

find_library(LOG_LIB log)
target_link_libraries(jarvis_whisper PRIVATE ggml ${LOG_LIB} android)
