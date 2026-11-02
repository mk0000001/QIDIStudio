# Fork-only preflight: fail explicitly rather than fabricate missing vendor code.
set(required_inputs
    src/slic3r/QIDI/UserPresetSyncManager.cpp
    src/slic3r/QIDI/UserPresetSyncManager.hpp
    deps/pgLibConnect/Lib/Windows/pgDllConnect.lib)
set(missing_inputs "")
foreach(input IN LISTS required_inputs)
    if(NOT EXISTS "${CMAKE_CURRENT_LIST_DIR}/../../${input}")
        string(APPEND missing_inputs "\n  ${input}")
    endif()
endforeach()
if(missing_inputs)
    message(FATAL_ERROR
        "Published QIDI source lacks required full-app build inputs:${missing_inputs}\n"
        "QDT_RELEASE_TO_PUBLIC=0 does not remove these unconditional requirements.\n"
        "Request the matching vendor source/SDK; a patched GUI cannot be built or validated yet.")
endif()
