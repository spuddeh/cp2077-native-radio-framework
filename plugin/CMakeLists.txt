cmake_minimum_required(VERSION 3.21)
project(RadioXL LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(RadioXL SHARED src/Main.cpp)

# RED4ext.SDK is header-only and lives in the read-only reference mirror. It is included, never
# built from there: nothing may write into _source.
target_include_directories(RadioXL PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../_source/RED4ext.SDK/include")

target_compile_definitions(RadioXL PRIVATE
    WIN32_LEAN_AND_MEAN NOMINMAX _CRT_SECURE_NO_WARNINGS)

set_target_properties(RadioXL PROPERTIES
    OUTPUT_NAME "RadioXL"
    SUFFIX ".dll")

# The manifest reader has no game dependency, so it is tested as a plain executable:
#   ctest --test-dir plugin\build -C Release --output-on-failure
enable_testing()
add_executable(RadioXLManifestTests tests/ManifestTests.cpp)
add_test(NAME manifest COMMAND RadioXLManifestTests)
