//
//  Tests/WindowResizeThemeTests.swift
//  Tests for the fixed-size window and the theme menu.
//  (The window is intentionally fixed at the original 730×470 design size —
//  no resizing — per the user's preference.)
//

import Foundation
import AppKit

enum WindowResizeThemeTests {
    static let suite = TestRunner.register("Window & theme", [

        TestCase("window content is the fixed design size 730×470 (at 1× zoom)") {
            // The window is sized at the design basis (730×470) multiplied by
            // the zoom factor. We test at 1× (zoom=0) so the saved zoom setting
            // doesn't make this test flaky.
            Settings.shared.zoom = 0
            let c = makeController()
            let factor = MainController.zoomFactor(Settings.shared.zoom)
            let s = c.window.contentView?.frame.size ?? .zero
            return expectAll(
                expectEqual(Int(s.width), Int(730 * factor), "content width"),
                expectEqual(Int(s.height), Int(470 * factor), "content height")
            )
        },

        TestCase("window is not resizable") {
            let c = makeController()
            return expectTrue(!c.window.styleMask.contains(.resizable),
                "window styleMask must NOT include .resizable")
        },

        TestCase("minSize == maxSize (locked at the zoomed size)") {
            Settings.shared.zoom = 0
            let c = makeController()
            let factor = MainController.zoomFactor(Settings.shared.zoom)
            return expectAll(
                expectEqual(Int(c.window.minSize.width), Int(730 * factor), "min width"),
                expectEqual(Int(c.window.minSize.height), Int(470 * factor), "min height"),
                expectEqual(Int(c.window.maxSize.width), Int(730 * factor), "max width"),
                expectEqual(Int(c.window.maxSize.height), Int(470 * factor), "max height")
            )
        },

        TestCase("theme setting is persisted (0/1/2)") {
            Settings.shared.theme = 2
            return expectEqual(Settings.shared.theme, 2, "theme value")
        },

        TestCase("applyTheme sets the app appearance for dark") {
            let c = makeController()
            c.applyTheme(2)   // dark
            let isDark = NSApp.appearance?.name == .darkAqua
            c.applyTheme(0)   // restore system
            return expectTrue(isDark, "applyTheme(2) should select a dark appearance")
        },
    ])
}

private func makeController() -> MainController {
    if Contest.shared == nil { _ = Contest() }
    makeKeyer()
    let c = MainController()
    MainController.shared = c
    return c
}

private func expectAll(_ results: TestResult...) -> TestResult {
    for r in results { if case .fail(let m) = r { return .fail(m) } }
    return .pass
}
