"""Run the contribution gate in ordered phases; propagate failures without modifying source."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
REPORTS = Path(".build/quality")
TOOLS = Path(".build/quality-tools")
PYTHON_TOOLS = Path(".build/quality-venv/bin")
PYTHON_SOURCES = ("scripts", "Tests/QualityTools", "Tests/CLI")


def run(*arguments, output=None):
    subprocess.run([str(value) for value in arguments], stdout=output, check=True)


def capture(*arguments):
    return subprocess.check_output(arguments, text=True).strip()


def check_environment(full=False):
    commands = ("git", "swift", "xcrun", "swiftlint", "rg", "shellcheck", "shfmt")
    executables = (PYTHON_TOOLS / "ruff", TOOLS / "swift-complexity")
    if full:
        commands += ("muter",)
        executables += (PYTHON_TOOLS / "diff-cover",)
    missing = [name for name in commands if shutil.which(name) is None]
    missing.extend(str(path) for path in executables if not os.access(path, os.X_OK))
    if missing:
        raise ValueError(f"Missing tools: {', '.join(missing)}. Run ./scripts/setup-quality.sh")
    expected = (
        (("swiftlint", "version"), "0.65.1"),
        (("shfmt", "--version"), "3.14.1"),
    )
    for command, required in expected:
        actual = capture(*command)
        if actual != required:
            raise ValueError(f"{' '.join(command)}: expected {required}, found {actual}")
    if "version: 0.11.0" not in capture("shellcheck", "--version"):
        raise ValueError("ShellCheck 0.11.0 required")
    if "Swift version 6.1.2" not in capture("swift", "--version"):
        raise ValueError("Select Xcode 16.4 (Swift 6.1.2)")


def check_sources():
    shell_scripts = sorted(Path("scripts").rglob("*.sh")) + [Path(".githooks/pre-commit")]
    run("shellcheck", "--external-sources", *shell_scripts)
    run("shfmt", "-d", "-i", "2", "-ci", *shell_scripts)
    run("xcrun", "swift-format", "lint", "--strict", "--recursive", "Sources", "Tests", "Package.swift")
    run("swiftlint", "lint", "--strict", "--quiet")
    run(PYTHON_TOOLS / "ruff", "check", *PYTHON_SOURCES)
    run(PYTHON_TOOLS / "ruff", "format", "--check", *PYTHON_SOURCES)
    run(sys.executable, "scripts/quality/architecture.py")
    run(sys.executable, "scripts/quality/catalogs.py")
    result = subprocess.run(
        ["rg", "-n", "swift-complexity:disable|swiftlint:disable", "Sources", "Tests", "--glob", "*.swift"],
        check=False,
    )
    if result.returncode == 0:
        raise ValueError("Inline quality suppressions are not allowed. Refactor or propose a policy change.")
    if result.returncode != 1:
        raise subprocess.CalledProcessError(result.returncode, result.args)


def check_complexity():
    analyzer = TOOLS / "swift-complexity"
    # The CLI threshold is inclusive: reject >=11 / >=16, allow <=10 / <=15.
    run(analyzer, "Sources", "--recursive", "--cyclomatic-only", "--threshold", "11")
    run(analyzer, "Sources", "--recursive", "--cognitive-only", "--threshold", "16")


def test_tooling():
    run(sys.executable, "-m", "unittest", "discover", "-s", "Tests/QualityTools", "-v")


def test_behavior():
    run("./scripts/fetch-engine.sh")
    run("swift", "build")
    os.environ["ARCBOX_CLI"] = str(Path(capture("swift", "build", "--show-bin-path")) / "arcbox")
    run(sys.executable, "-m", "unittest", "discover", "-s", "Tests/CLI", "-v")
    run("swift", "test", "--enable-code-coverage")


def collect_coverage():
    binaries = Path(capture("swift", "build", "--show-bin-path"))
    shutil.copyfile(binaries / "codecov/Arcbox.json", REPORTS / "coverage.json")
    with (REPORTS / "coverage.lcov").open("w") as output:
        run(
            "xcrun",
            "llvm-cov",
            "export",
            "-format=lcov",
            "-instr-profile",
            binaries / "codecov/default.profdata",
            binaries / "ArcboxPackageTests.xctest/Contents/MacOS/ArcboxPackageTests",
            output=output,
        )
    # Threshold zero requests every function; metrics.py applies distinct 10/15 limits.
    with (REPORTS / "complexity.json").open("w") as output:
        result = subprocess.run(
            [str(TOOLS / "swift-complexity"), "Sources", "--recursive", "--format", "json", "--threshold", "0"],
            stdout=output,
            check=False,
        )
    if result.returncode not in (0, 1):
        raise subprocess.CalledProcessError(result.returncode, result.args)


def check_metrics(base):
    collect_coverage()
    run(sys.executable, "scripts/quality/metrics.py")
    run(
        PYTHON_TOOLS / "diff-cover",
        REPORTS / "coverage.xml",
        "--compare-branch",
        base,
        "--fail-under",
        "80",
        "--format",
        f"json:{REPORTS}/diff-coverage.json",
        "--format",
        f"html:{REPORTS}/diff-coverage.html",
    )


def execute_phases(phases):
    for name, action in phases:
        print(f"→ {name}", flush=True)
        action()


def main(arguments=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="origin/main", help="Git revision for changed-line coverage")
    parser.add_argument(
        "--full", action="store_true", help="Also build/test the app, measure coverage and run mutations"
    )
    options = parser.parse_args(arguments)
    os.chdir(ROOT)
    try:
        run("git", "rev-parse", "--verify", "--end-of-options", f"{options.base}^{{commit}}", output=subprocess.DEVNULL)
        REPORTS.mkdir(parents=True, exist_ok=True)
        phases = [
            ("Local tools", lambda: check_environment(options.full)),
            ("Formatting, lint and module boundaries", check_sources),
            ("Swift complexity", check_complexity),
            ("Tooling behavior", test_tooling),
        ]
        if options.full:
            phases.extend(
                [
                    ("Application build and tests", test_behavior),
                    ("Coverage and CRAP", lambda: check_metrics(options.base)),
                    ("Mutation testing", lambda: run("./scripts/quality/mutation.sh")),
                ]
            )
        execute_phases(phases)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Quality gate failed: {error}", file=sys.stderr)
        return 1
    print("Full quality gate passed." if options.full else "Local quality checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
