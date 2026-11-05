#include <catch2/catch.hpp>

#include "libslic3r/PrintConfig.hpp"
#include "libslic3r/Utils.hpp"

#include <string>
#include <vector>

using namespace Slic3r;

TEST_CASE("CLI datadir parses split and equals forms without consuming model arguments", "[Config][CLI]")
{
    DynamicPrintAndCLIConfig config;
    t_config_option_keys files;
    t_config_option_keys order;
    const std::string directory = u8"isolated profiles/\uD14C\uC2A4\uD2B8";
    const std::string previous_data_dir = data_dir();

    SECTION("Separate value") {
        const char* argv[] {"qidi-studio", "--datadir", directory.c_str(), "sample.3mf"};
        REQUIRE(config.read_cli(4, argv, &files, &order));
    }
    SECTION("Equals value") {
        const std::string option = "--datadir=" + directory;
        const char* argv[] {"qidi-studio", option.c_str(), "sample.3mf"};
        REQUIRE(config.read_cli(3, argv, &files, &order));
    }

    REQUIRE(config.opt_string("datadir") == directory);
    REQUIRE(files == t_config_option_keys {"sample.3mf"});
    REQUIRE(order == t_config_option_keys {"datadir"});
    // Parsing records the option; application setup applies it later.
    REQUIRE(data_dir() == previous_data_dir);
}

TEST_CASE("CLI datadir is optional and defaults to an empty string", "[Config][CLI]")
{
    DynamicPrintAndCLIConfig config;
    t_config_option_keys files;
    const std::string previous_data_dir = data_dir();
    const char* argv[] {"qidi-studio"};
    REQUIRE(config.read_cli(1, argv, &files));
    REQUIRE_FALSE(config.has("datadir"));
    REQUIRE(files.empty());

    const auto* option = config.option<ConfigOptionString>("datadir", true);
    REQUIRE(option != nullptr);
    REQUIRE(option->value.empty());
    REQUIRE(data_dir() == previous_data_dir);
}

TEST_CASE("CLI datadir preserves an explicitly empty argument", "[Config][CLI]")
{
    DynamicPrintAndCLIConfig config;
    t_config_option_keys files;
    const std::string previous_data_dir = data_dir();
    const char* argv[] {"qidi-studio", "--datadir", ""};
    REQUIRE(config.read_cli(3, argv, &files));
    REQUIRE(config.has("datadir"));
    REQUIRE(config.opt_string("datadir").empty());
    REQUIRE(data_dir() == previous_data_dir);
}

TEST_CASE("CLI datadir preserves an empty equals value and positional models", "[Config][CLI]")
{
    DynamicPrintAndCLIConfig config;
    t_config_option_keys files;
    t_config_option_keys order;
    const std::string previous_data_dir = data_dir();

    SECTION("Empty equals value alone") {
        const char* argv[] {"qidi-studio", "--datadir="};
        REQUIRE(config.read_cli(2, argv, &files, &order));
        REQUIRE(files.empty());
    }
    SECTION("Empty equals value before a model") {
        const char* argv[] {"qidi-studio", "--datadir=", "sample.3mf"};
        REQUIRE(config.read_cli(3, argv, &files, &order));
        REQUIRE(files == t_config_option_keys {"sample.3mf"});
    }

    REQUIRE(config.has("datadir"));
    REQUIRE(config.opt_string("datadir").empty());
    REQUIRE(order == t_config_option_keys {"datadir"});
    REQUIRE(data_dir() == previous_data_dir);
}

TEST_CASE("Empty scalar CLI strings preserve boolean and list option parsing", "[Config][CLI]")
{
    DynamicPrintAndCLIConfig config;
    t_config_option_keys files;
    const char* argv[] {"qidi-studio", "--outputdir=", "--help",
                        "--load-settings", "first.json;second.json", "sample.3mf"};
    REQUIRE(config.read_cli(6, argv, &files));
    REQUIRE(config.opt_string("outputdir").empty());
    REQUIRE(config.opt_bool("help"));
    REQUIRE(config.option<ConfigOptionStrings>("load_settings")->values ==
            std::vector<std::string> {"first.json", "second.json"});
    REQUIRE(files == t_config_option_keys {"sample.3mf"});
}
