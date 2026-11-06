# Account-free CLI and recent-project state contracts only. Legacy suites remain
# registered separately, with their existing compilation failures unchanged.
add_executable(qidi_beta_regression_tests
    ../gpu_geometry/main.cpp
    ../libslic3r/test_cli_datadir.cpp
    ../libslic3r/test_config_enum_maps.cpp
    ../gpu_geometry/test_gcode_optional_result.cpp
    ../libslic3r/test_preset_include_diff_cache.cpp
    ../slic3rutils/recent_projects_refresh_tests.cpp)
target_compile_features(qidi_beta_regression_tests PRIVATE cxx_std_17)
target_include_directories(qidi_beta_regression_tests PRIVATE "${PROJECT_SOURCE_DIR}/src")
# Config/Utils/AppConfig pull the same logging/crypto providers as the app.
target_link_libraries(qidi_beta_regression_tests PRIVATE test_common libslic3r libslic3r_gui)
if(WIN32)
    target_link_libraries(qidi_beta_regression_tests PRIVATE bcrypt)
endif()
set_property(TARGET qidi_beta_regression_tests PROPERTY FOLDER "tests")
add_test(NAME qidi_beta_regression_tests COMMAND qidi_beta_regression_tests)
