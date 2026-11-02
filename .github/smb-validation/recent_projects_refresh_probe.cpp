// Fork-only Windows diagnostic. Reads local UTF-8 paths; never prints the paths.
#define NOMINMAX
#include <windows.h>

#include "slic3r/GUI/RecentProjectsRefresh.hpp"

#include <chrono>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

int main(int argc, char **argv)
{
    if (argc != 2) {
        std::cerr << "Usage: recent_projects_refresh_probe <UTF-8 paths file>\n";
        return 2;
    }
    std::ifstream input(argv[1]);
    if (!input) {
        std::cerr << "Cannot open paths file\n";
        return 2;
    }
    std::vector<std::wstring> paths;
    for (std::string line; std::getline(input, line);) {
        if (!line.empty() && line.back() == '\r')
            line.pop_back();
        if (line.empty())
            continue;
        const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, line.data(), int(line.size()), nullptr, 0);
        if (size == 0) {
            std::cerr << "Invalid UTF-8 in paths file\n";
            return 2;
        }
        std::wstring wide(size, L'\0');
        MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, line.data(), int(line.size()), wide.data(), size);
        paths.push_back(std::move(wide));
    }
    size_t queries = 0;
    const auto scan = [&] {
        for (const auto &path : paths) {
            ++queries;
            HANDLE file = CreateFileW(path.c_str(), FILE_READ_ATTRIBUTES | FILE_READ_EA,
                FILE_SHARE_DELETE | FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
            if (file != INVALID_HANDLE_VALUE) {
                FILETIME timestamp;
                GetFileTime(file, nullptr, nullptr, &timestamp);
                CloseHandle(file);
            }
        }
    };
    const auto elapsed_ms = [](auto start) {
        return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    };

    auto start = std::chrono::steady_clock::now();
    scan();
    scan();
    const double baseline_ms = elapsed_ms(start);
    const size_t baseline_queries = queries;

    queries = 0;
    Slic3r::GUI::RecentProjectsRefresh refresh;
    start = std::chrono::steady_clock::now();
    for (int save_notification = 0; save_notification < 2; ++save_notification) {
        refresh.request(0);
        if (refresh.take(false))
            scan();
    }
    const double hidden_ms = elapsed_ms(start);
    const size_t hidden_queries = queries;

    start = std::chrono::steady_clock::now();
    if (refresh.take(true))
        scan();
    const double home_ms = elapsed_ms(start);

    std::cout << "{\"scope\":\"metadata component benchmark, not a GUI save\","
              << "\"history_entries\":" << paths.size()
              << ",\"baseline_queries\":" << baseline_queries
              << ",\"baseline_ms\":" << baseline_ms
              << ",\"patched_hidden_queries\":" << hidden_queries
              << ",\"patched_hidden_ms\":" << hidden_ms
              << ",\"return_home_queries\":" << queries - hidden_queries
              << ",\"return_home_ms\":" << home_ms << "}\n";
}
