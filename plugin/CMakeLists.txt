cmake_minimum_required(VERSION 3.21)
project(NativeRadioFramework LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(NativeRadioFramework SHARED src/Main.cpp)

# RED4ext.SDK is header-only and lives in the read-only reference mirror. It is included, never
# built from there: nothing may write into _source.
target_include_directories(NativeRadioFramework PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../_source/RED4ext.SDK/include")

target_compile_definitions(NativeRadioFramework PRIVATE
    WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS RED4EXT_HEADER_ONLY)

set_target_properties(NativeRadioFramework PROPERTIES
    OUTPUT_NAME "NativeRadioFramework"
    SUFFIX ".dll")
