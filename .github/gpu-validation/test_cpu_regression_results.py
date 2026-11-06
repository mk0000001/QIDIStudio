"""Host-only XML boundary tests. Synthetic reports are never native test proof."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
SOURCES = {
    "cache": REPO / "tests/libslic3r/test_preset_include_diff_cache.cpp",
    "enum": REPO / "tests/libslic3r/test_config_enum_maps.cpp",
    "guard": REPO / "tests/gpu_geometry/test_gcode_optional_result.cpp",
}
NAMES = {
    "cache": [
        "Preset include differences are computed lazily once per object pair",
        "Preset include differences distinguish both config identities",
        "Preset category reset discards differences before address reuse",
        "Empty preset include differences are cached",
        "Failed preset include computations are retried",
        "Cached includes preserve application order and exact resulting config",
        "Default snapshots survive deque movement",
        "Default snapshots distinguish reused source addresses and reset with categories",
        "Reused include keys preserve each inherited parent's unrelated values",
    ],
    "enum": [
        "QIDI enum factories bind the nine print definition maps",
        "QIDI default copy and apply paths retain enum maps",
        "QIDI resetting static defaults restores definition enum maps",
        "QIDI enum value assignment preserves the destination map",
    ],
    "guard": ["G-code export accepts an optional processor result"],
}
SECTIONS = ["A null result exports without preview data", "A provided result receives the object label flag"]


def report(kind, successes=None):
    root = ET.Element("Catch", name="SYNTHETIC_XML_BOUNDARY_FIXTURE_NOT_NATIVE_PROOF")
    group = ET.SubElement(root, "Group")
    for name in NAMES[kind]:
        case = ET.SubElement(group, "TestCase", name=name)
        if kind == "guard":
            for name in SECTIONS:
                section = ET.SubElement(case, "Section", name=name)
                ET.SubElement(section, "OverallResults", successes="1", failures="0", expectedFailures="0")
        ET.SubElement(case, "OverallResult", success="true")
    ET.SubElement(root, "OverallResults", successes=str(successes if successes is not None else {"cache": 39, "enum": 670, "guard": 7}[kind]), failures="0", expectedFailures="0")
    ET.SubElement(root, "OverallResultsCases", successes=str(len(NAMES[kind])), failures="0", expectedFailures="0")
    return root


class Results(unittest.TestCase):
    def setUp(self):
        checker = HERE / "check_cpu_regression_results.py"
        self.assertTrue(checker.is_file(), "The new CPU regression gate has not been implemented")
        spec = importlib.util.spec_from_file_location("cpu_gate", checker)
        self.gate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.gate)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.xml = Path(self.temp.name) / "result.xml"

    def verify(self, kind, root=None, code=0, source=None):
        ET.ElementTree(root if root is not None else report(kind)).write(self.xml, encoding="utf-8")
        return self.gate.verify(self.xml, source or SOURCES[kind], kind, code)

    def reject(self, kind, root):
        with self.assertRaises(ValueError):
            self.verify(kind, root)

    def test_cache_exact_registered_cases_and_totals(self):
        result = self.verify("cache")
        self.assertEqual((result["successful_assertions"], result["registered_cases"]), (39, 9))

    def test_enum_exact_registered_cases_and_totals(self):
        result = self.verify("enum")
        self.assertEqual((result["successful_assertions"], result["registered_cases"]), (670, 4))

    def test_guard_reports_observed_count_instead_of_guessing(self):
        for count in (7, 27):
            with self.subTest(count=count):
                self.assertEqual(self.verify("guard", report("guard", count))["successful_assertions"], count)

    def test_nonzero_process_exit_rejects_even_successful_xml(self):
        for code in (1, -1073741819):
            with self.subTest(code=code), self.assertRaises(ValueError):
                self.verify("guard", code=code)

    def test_missing_case_cannot_hide_behind_correct_totals(self):
        root = report("cache")
        root.find("Group").remove(root.find(".//TestCase"))
        self.reject("cache", root)

    def test_replaced_case_with_same_cardinality_rejects(self):
        root = report("enum")
        root.find(".//TestCase").set("name", "unrelated case")
        self.reject("enum", root)

    def test_duplicate_case_rejects(self):
        root = report("cache")
        root.findall(".//TestCase")[1].set("name", NAMES["cache"][0])
        self.reject("cache", root)

    def test_failed_case_rejects_even_successful_run_totals(self):
        root = report("enum")
        root.find(".//OverallResult").set("success", "false")
        self.reject("enum", root)

    def test_missing_case_result_rejects(self):
        root = report("cache")
        case = root.find(".//TestCase")
        case.remove(case.find("OverallResult"))
        self.reject("cache", root)

    def test_missing_guard_section_rejects(self):
        root = report("guard")
        root.find(".//TestCase").remove(root.find(".//Section"))
        self.reject("guard", root)

    def test_duplicate_guard_section_rejects(self):
        root = report("guard")
        root.findall(".//Section")[1].set("name", SECTIONS[0])
        self.reject("guard", root)

    def test_guard_section_failure_rejects(self):
        root = report("guard")
        root.find(".//Section/OverallResults").set("failures", "1")
        self.reject("guard", root)

    def test_guard_section_without_assertions_rejects(self):
        root = report("guard")
        root.find(".//Section/OverallResults").set("successes", "0")
        self.reject("guard", root)

    def test_guard_missing_section_totals_rejects(self):
        root = report("guard")
        section = root.find(".//Section")
        section.remove(section.find("OverallResults"))
        self.reject("guard", root)

    def test_duplicate_run_totals_rejects(self):
        root = report("cache")
        ET.SubElement(root, "OverallResults", successes="39", failures="0", expectedFailures="0")
        self.reject("cache", root)

    def test_guard_zero_total_rejects(self):
        self.reject("guard", report("guard", 0))

    def test_wrong_exact_assertion_count_rejects(self):
        for kind, count in (("cache", 38), ("enum", 669)):
            with self.subTest(kind=kind):
                self.reject(kind, report(kind, count))

    def test_failed_or_expected_failure_totals_reject(self):
        for field in ("failures", "expectedFailures"):
            root = report("cache")
            root.find("OverallResults").set(field, "1")
            with self.subTest(field=field):
                self.reject("cache", root)

    def test_missing_malformed_or_negative_counter_rejects(self):
        for value in (None, "garbage", "-1"):
            root = report("cache")
            totals = root.find("OverallResults")
            if value is None:
                del totals.attrib["successes"]
            else:
                totals.set("successes", value)
            with self.subTest(value=value):
                self.reject("cache", root)

    def test_missing_or_wrong_case_totals_reject(self):
        for value in (None, "0", "8"):
            root = report("cache")
            if value is None:
                root.remove(root.find("OverallResultsCases"))
            else:
                root.find("OverallResultsCases").set("successes", value)
            with self.subTest(value=value):
                self.reject("cache", root)

    def test_junit_is_not_native_catch_case_proof(self):
        root = report("cache")
        root.tag = "testsuites"
        self.reject("cache", root)

    def test_malformed_xml_rejects(self):
        self.xml.write_text("<Catch>", encoding="utf-8")
        with self.assertRaises(ValueError):
            self.gate.verify(self.xml, SOURCES["cache"], "cache", 0)

    def test_source_case_identity_mismatch_rejects(self):
        source = Path(self.temp.name) / "changed.cpp"
        source.write_text(SOURCES["cache"].read_text(encoding="utf-8").replace(NAMES["cache"][0], "changed case"), encoding="utf-8")
        with self.assertRaises(ValueError):
            self.verify("cache", source=source)

    def test_guard_source_section_mismatch_rejects(self):
        source = Path(self.temp.name) / "changed.cpp"
        source.write_text(SOURCES["guard"].read_text(encoding="utf-8").replace(SECTIONS[0], "changed section"), encoding="utf-8")
        with self.assertRaises(ValueError):
            self.verify("guard", source=source)

    def test_unknown_contract_rejects(self):
        with self.assertRaises(ValueError):
            self.gate.verify(self.xml, SOURCES["cache"], "unknown", 0)

    def test_cli_failure_exit_not_successful_receipt(self):
        ET.ElementTree(report("cache", 1)).write(self.xml)
        run = subprocess.run([sys.executable, str(HERE / "check_cpu_regression_results.py"), "--kind", "cache", "--source", str(SOURCES["cache"]), "--xml", str(self.xml), "--exit-code", "0"], capture_output=True, text=True)
        self.assertNotEqual(run.returncode, 0)
        self.assertNotIn('"status": "ACTUAL_NATIVE_CPU_REGRESSION_PASS"', run.stdout)


if __name__ == "__main__":
    unittest.main()
