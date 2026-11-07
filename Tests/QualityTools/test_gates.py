"""Observable failure behavior of the quality gates, using synthetic reports."""

import importlib.util
from pathlib import Path
import unittest


def module(name):
    spec = importlib.util.spec_from_file_location(name, Path("scripts/quality") / f"{name}.py")
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


metrics = module("metrics")
architecture = module("architecture")


class QualityGateTests(unittest.TestCase):
    def test_crap_formula_and_coverage_boundaries(self):
        self.assertEqual(metrics.crap(10, 1), 10)
        self.assertEqual(metrics.crap(10, 0), 110)
        self.assertAlmostEqual(metrics.crap(4, 0.5), 6)

    def test_cycles_and_reverse_adapter_dependencies_fail(self):
        for graph in [
            [{"name": "one", "target_dependencies": ["two"]}, {"name": "two", "target_dependencies": ["one"]}],
            [{"name": "ArcboxCore", "target_dependencies": ["ArcboxApp"]}],
        ]:
            with self.assertRaises(ValueError):
                architecture.validate(graph)
        architecture.validate(
            [
                {"name": "ArcboxCore"},
                {"name": "ArcboxApp", "target_dependencies": ["ArcboxCore"]},
                {"name": "ArcboxCLI", "target_dependencies": ["ArcboxCore"]},
            ]
        )

    def test_empty_measurements_fail_closed(self):
        with self.assertRaises(ValueError):
            metrics.report({"files": []}, {}, [])

    def test_high_complexity_and_uncovered_code_fail(self):
        path = metrics.CORE / "Example.swift"
        function = dict(location=dict(line=1), name="unsafe", cyclomaticComplexity=11, cognitiveComplexity=16)
        source = dict(filePath=str(path), functions=[function])
        result = metrics.report({"files": [source]}, {path: {2: 0}}, [])
        self.assertEqual(result["crap_max"], 132)
        self.assertEqual(len(result["violations"]), 3)

    def test_function_coverage_uses_llvm_region_not_following_function(self):
        path = metrics.CORE / "Example.swift"
        llvm = [dict(filenames=[str(path)], regions=[[2, 1, 4, 1, 1, 0, 0, 0]])]
        coverage, region = metrics.function_coverage(
            dict(location=dict(line=1)), 5, path, {2: 1, 3: 0, 4: 1, 6: 0}, llvm
        )
        self.assertEqual(region, [2, 4])
        self.assertAlmostEqual(coverage, 2 / 3)


if __name__ == "__main__":
    unittest.main()
