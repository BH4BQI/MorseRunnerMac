//
//  AppDelegate.swift
//  Application delegate — boots the main controller on launch.
//

import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let controller = MainController()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        controller.show()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        controller.saveSettings()
        Settings.shared.runMode = .stop
    }
}
