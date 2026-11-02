cmake_minimum_required(VERSION 3.16)
project(QidiSmbSaveValidation LANGUAGES CXX)

enable_testing()
add_executable(recent_projects_refresh_tests
    ../../tests/slic3rutils/recent_projects_refresh_tests.cpp)
target_compile_features(recent_projects_refresh_tests PRIVATE cxx_std_17)
target_compile_definitions(recent_projects_refresh_tests PRIVATE CATCH_CONFIG_MAIN)
target_include_directories(recent_projects_refresh_tests PRIVATE ../../src ../../tests)
add_test(NAME recent_projects_refresh COMMAND recent_projects_refresh_tests)

if(WIN32)
    add_executable(recent_projects_refresh_probe recent_projects_refresh_probe.cpp)
    target_compile_features(recent_projects_refresh_probe PRIVATE cxx_std_17)
    target_include_directories(recent_projects_refresh_probe PRIVATE ../../src)
endif()
