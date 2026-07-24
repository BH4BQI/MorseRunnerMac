//
//  Tests/TestRunner.swift
//  A minimal, XCTest-free test runner.
//
//  This environment only ships Apple's Command Line Tools (no Xcode/XCTest),
//  so we provide a tiny assertion-based runner invoked by `--run-tests`. It
//  collects pass/fail counts and exits non-zero on any failure — usable from
//  CI / the usual `swift build && ./run-tests` workflow.
//

import Foundation

public enum TestResult {
    case pass
    case fail(String)
    case skip(String)
}

public final class TestCase {
    public let name: String
    public let run: () -> TestResult
    public init(_ name: String, _ run: @escaping () -> TestResult) {
        self.name = name; self.run = run
    }
}

public enum TestRunner {
    /// Registry of all test cases, grouped by suite. Add new suites here.
    public static var suites: [(String, [TestCase])] = []

    @discardableResult
    public static func register(_ suite: String, _ cases: [TestCase]) -> [TestCase] {
        suites.append((suite, cases))
        return cases
    }

    /// Run all registered tests. Returns true if all passed.
    @discardableResult
    public static func runAll() -> Bool {
        // Force the per-suite top-level `let suite = register(...)` to execute.
        // (Swift only runs a file's top-level code if it's referenced.)
        _ = MyStationTests.suite
        _ = MorseKeyTests.suite
        _ = DxOperatorTests.suite
        _ = AudioPipelineTests.suite
        _ = ContestFlowTests.suite
        _ = MessageTests.suite
        _ = CWRoundTripTests.suite
        _ = FormatterTests.suite
        _ = ESMFlowTests.suite
        _ = FieldEditorDispatchTests.suite
        _ = RunButtonTests.suite
        _ = AudioThreadSafetyTests.suite
        _ = HistogramTests.suite
        _ = TabCycleTests.suite
        _ = WindowResizeThemeTests.suite
        _ = ProbeTests.suite

        var passed = 0, failed = 0
        print("=== MorseRunner test run ===")
        for (suite, cases) in suites {
            print("\n[\(suite)]")
            for tc in cases {
                switch tc.run() {
                case .pass:
                    passed += 1
                    print("  ✓ \(tc.name)")
                case .fail(let msg):
                    failed += 1
                    print("  ✗ \(tc.name)  — \(msg)")
                case .skip(let msg):
                    print("  · \(tc.name)  (skipped: \(msg))")
                }
            }
        }
        print("\n=== \(passed) passed, \(failed) failed ===")
        return failed == 0
    }
}

// MARK: - assertion helpers used by tests

@discardableResult
public func expectTrue(_ condition: @autoclosure () -> Bool,
                       _ message: String = "") -> TestResult {
    return condition() ? .pass : .fail(message.isEmpty ? "expected true" : message)
}

@discardableResult
public func expectFalse(_ condition: @autoclosure () -> Bool,
                        _ message: String = "") -> TestResult {
    return condition() ? .fail(message.isEmpty ? "expected false" : message) : .pass
}

public func expectEqual<T: Equatable>(_ a: T, _ b: T, _ name: String = "") -> TestResult {
    return a == b ? .pass : .fail("\(name.isEmpty ? "values" : name): expected \(b), got \(a)")
}

public func expectApprox(_ a: Double, _ b: Double, accuracy: Double,
                         _ name: String = "") -> TestResult {
    return abs(a - b) <= accuracy
        ? .pass
        : .fail("\(name.isEmpty ? "value" : name): expected \(b) ± \(accuracy), got \(a)")
}
