"""Combine SwiftSyntax complexity with LLVM executable-line coverage (not path coverage)."""

import json
import sys
from pathlib import Path
from xml.etree.ElementTree import Element, SubElement, ElementTree

ROOT = Path.cwd()
CORE = ROOT / "Sources/ArcboxCore"


def read_lcov(path):
    files = {}
    current = None
    for line in Path(path).read_text().splitlines():
        if line.startswith("SF:"):
            current = Path(line[3:]).resolve()
            files[current] = {}
        elif line.startswith("DA:") and current is not None:
            number, hits = line[3:].split(",")[:2]
            files[current][int(number)] = int(hits)
    return files


def function_coverage(function, following_line, path, lines, llvm):
    start = function["location"]["line"]
    # LLVM's outer code region begins at the opening brace, sometimes after a multiline signature.
    regions = [
        r
        for f in llvm
        for r in f["regions"]
        if Path(f["filenames"][r[5]]).resolve() == path and start <= r[0] < following_line
    ]
    if not regions:
        return 0.0, None
    first = min(r[0] for r in regions)
    end = max(r[2] for r in regions if r[0] == first)
    counts = [hits for line, hits in lines.items() if first <= line <= end]
    return sum(hits > 0 for hits in counts) / len(counts) if counts else 0.0, [first, end]


def crap(complexity, coverage):
    return complexity**2 * (1 - coverage) ** 3 + complexity


def cobertura(files, output):
    root = Element("coverage")
    sources = SubElement(root, "sources")
    SubElement(sources, "source").text = str(ROOT)
    classes = SubElement(SubElement(SubElement(root, "packages"), "package", name="ArcboxCore"), "classes")
    for path, counts in files.items():
        if path.parent != CORE:
            continue
        item = SubElement(classes, "class", name=path.stem, filename=str(path.relative_to(ROOT)))
        lines = SubElement(item, "lines")
        for number, hits in sorted(counts.items()):
            SubElement(lines, "line", number=str(number), hits=str(hits))
    ElementTree(root).write(output, encoding="utf-8", xml_declaration=True)


def report(complexity, files, llvm):
    functions = []
    violations = []
    for source in complexity["files"]:
        path = Path(source["filePath"]).resolve()
        methods = sorted(source["functions"], key=lambda value: value["location"]["line"])
        for index, function in enumerate(methods):
            cc = function["cyclomaticComplexity"]
            cognitive = function["cognitiveComplexity"]
            label = f"{path.relative_to(ROOT)}:{function['location']['line']} {function['name']}"
            if cc > 10 or cognitive > 15:
                violations.append(f"{label}: cyclomatic={cc} (max 10), cognitive={cognitive} (max 15)")
            if path.parent != CORE:
                continue
            end = methods[index + 1]["location"]["line"] if index + 1 < len(methods) else sys.maxsize
            coverage, region = function_coverage(function, end, path, files.get(path, {}), llvm)
            score = crap(cc, coverage)
            functions.append(
                dict(
                    name=label,
                    cyclomatic=cc,
                    cognitive=cognitive,
                    line_coverage=coverage,
                    llvm_region=region,
                    crap=score,
                )
            )
            if score > 30:
                violations.append(f"{label}: CRAP(line)={score:.2f} (max 30)")
    if not functions:
        raise ValueError("No core functions measured; refusing an empty report")
    average = sum(f["crap"] for f in functions) / len(functions)
    if average >= 5:
        violations.append(f"Average CRAP(line)={average:.2f} (must be < 5)")
    core_lines = [hits for path, counts in files.items() if path.parent == CORE for hits in counts.values()]
    if not core_lines:
        raise ValueError("No core coverage data")
    return dict(
        crap_average=average,
        crap_max=max(f["crap"] for f in functions),
        core_line_coverage=sum(v > 0 for v in core_lines) / len(core_lines),
        functions=functions,
        violations=violations,
    )


def main():
    directory = Path(".build/quality")
    complexity = json.loads((directory / "complexity.json").read_text())
    coverage = json.loads((directory / "coverage.json").read_text())
    llvm = [function for data in coverage["data"] for function in data["functions"]]
    files = read_lcov(directory / "coverage.lcov")
    result = report(complexity, files, llvm)
    (directory / "metrics.json").write_text(json.dumps(result, indent=2) + "\n")
    cobertura(files, directory / "coverage.xml")
    print(
        f"Core line coverage: {result['core_line_coverage']:.1%}; CRAP(line) avg={result['crap_average']:.2f}, max={result['crap_max']:.2f}"
    )
    for violation in result["violations"]:
        print(violation, file=sys.stderr)
    return bool(result["violations"])


if __name__ == "__main__":
    sys.exit(main())
