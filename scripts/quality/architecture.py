"""Check the resolved SwiftPM module graph and the core/adapters boundary."""

import json
import subprocess


def validate(targets):
    graph = {target["name"]: target.get("target_dependencies", []) for target in targets}
    active, done = set(), set()

    def visit(name):
        if name in active:
            raise ValueError(f"Circular module dependency at {name}")
        if name in done:
            return
        active.add(name)
        for dependency in graph.get(name, []):
            visit(dependency)
        active.remove(name)
        done.add(name)

    for name in graph:
        visit(name)
    if graph.get("ArcboxCore"):
        raise ValueError("ArcboxCore must not depend on app, CLI or tests")
    for adapter in ("ArcboxApp", "ArcboxCLI"):
        if graph.get(adapter) != ["ArcboxCore"]:
            raise ValueError(f"{adapter} must depend only on ArcboxCore")


def main():
    result = subprocess.run(
        ["swift", "package", "describe", "--type", "json"], check=True, capture_output=True, text=True
    )
    validate(json.loads(result.stdout)["targets"])
    print("SwiftPM module cycles: 0; core/adapters boundary: OK")


if __name__ == "__main__":
    main()
