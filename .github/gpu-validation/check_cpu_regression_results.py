"""Check focused native Catch results; hosted tests do not establish hardware or speed."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

CONTRACTS = {"cache": ("PresetIncludeDiffCache", 9, 39), "enum": ("EnumMaps", 4, 670), "guard": ("OptionalResult", 1, None)}
GUARD_SECTIONS = {"A null result exports without preview data", "A provided result receives the object label flag"}


def totals(node):
    if node is None:
        raise ValueError("Native Catch totals missing")
    try:
        values = tuple(int(node.attrib[key]) for key in ("successes", "failures", "expectedFailures"))
    except (KeyError, ValueError) as exc:
        raise ValueError("Malformed Catch counters") from exc
    if min(values) < 0 or values[1:] != (0, 0):
        raise ValueError("Failed, expected-failed or negative Catch counters")
    return values[0]


def verify(xml_path, source_path, kind, exit_code):
    if kind not in CONTRACTS or exit_code != 0:
        raise ValueError("Unknown contract or unsuccessful executable exit")
    tag, count, expected_assertions = CONTRACTS[kind]
    try:
        root = ET.parse(xml_path).getroot()
    except ET.ParseError as exc:
        raise ValueError("Malformed native Catch XML") from exc
    if root.tag not in ("Catch", "Catch2TestRun"):
        raise ValueError("Expected native Catch XML, not JUnit section counts")
    if any(len(root.findall(name)) != 1 for name in ("OverallResults", "OverallResultsCases")):
        raise ValueError("Missing or ambiguous native Catch run totals")
    assertions = totals(root.find("OverallResults"))
    cases = totals(root.find("OverallResultsCases"))
    if cases != count or assertions <= 0 or (expected_assertions is not None and assertions != expected_assertions):
        raise ValueError("Unexpected native Catch case/assertion totals")
    source_bytes = Path(source_path).read_bytes()
    source = source_bytes.decode("utf-8-sig")
    declared = re.findall(r'^\s*TEST_CASE\s*\(\s*"([^"\n]+)"\s*,\s*"([^"\n]+)"\s*\)', source, re.MULTILINE)
    expected = [name for name, tags in declared if "[" + tag + "]" in tags]
    actual_nodes = root.findall(".//TestCase")
    actual = [node.get("name") for node in actual_nodes]
    if len(expected) != count or len(set(expected)) != count or len(actual) != count or set(actual) != set(expected):
        raise ValueError("Actual registered cases differ from the focused source contract")
    for case in actual_nodes:
        results = case.findall("OverallResult")
        if len(results) != 1 or results[0].get("success") != "true":
            raise ValueError("Missing or unsuccessful case result")
    for node in root.findall(".//OverallResults") + root.findall(".//OverallResultsCases"):
        totals(node)
    if kind == "guard":
        source_sections = re.findall(r'\bSECTION\s*\(\s*"([^"\n]+)"\s*\)', source)
        sections = actual_nodes[0].findall(".//Section")
        if len(source_sections) != 2 or set(source_sections) != GUARD_SECTIONS or len(sections) != 2 or {section.get("name") for section in sections} != GUARD_SECTIONS:
            raise ValueError("Both exact optional-result sections must execute")
        for section in sections:
            if len(section.findall("OverallResults")) != 1 or totals(section.find("OverallResults")) <= 0:
                raise ValueError("Optional-result section assertions missing")
    return {"status": "ACTUAL_NATIVE_CPU_REGRESSION_PASS", "kind": kind, "successful_assertions": assertions, "registered_cases": cases, "case_names": actual, "source_sha256": hashlib.sha256(source_bytes).hexdigest(), "xml_sha256": hashlib.sha256(Path(xml_path).read_bytes()).hexdigest(), "executable_exit_code": exit_code, "hardware_or_speedup_proof": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--xml", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--kind", choices=CONTRACTS, required=True)
    parser.add_argument("--exit-code", type=int, required=True)
    args = parser.parse_args()
    print(json.dumps(verify(args.xml, args.source, args.kind, args.exit_code)))
