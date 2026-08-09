//
//  ScoreDialog.swift
//  Port of ScoreDlg.pas — score string dialog.
//
//  Shown at the end of a WPX session. Lets the user copy the score string,
//  view the scoreboard, or submit it to the configured web server.
//

import AppKit

public final class ScoreDialog: NSWindowController {
    public let scoreString: String
    public let isHiScore: Bool

    public init(scoreString: String, isHiScore: Bool) {
        self.scoreString = scoreString
        self.isHiScore = isHiScore
        let rect = NSRect(x: 0, y: 0, width: 460, height: isHiScore ? 200 : 140)
        let win = NSWindow(contentRect: rect,
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "Morse Runner Score"
        super.init(window: win)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        guard let cv = window?.contentView else { return }
        let label = NSTextField(labelWithString: "Your score string:")
        label.frame = NSRect(x: 20, y: cv.bounds.maxY - 30, width: 200, height: 20)
        cv.addSubview(label)

        let field = NSTextField(string: scoreString)
        field.frame = NSRect(x: 20, y: cv.bounds.maxY - 56, width: 420, height: 24)
        field.isEditable = true
        field.tag = 100
        cv.addSubview(field)

        var y: CGFloat = 20
        let submit = NSButton(title: "Submit", target: self, action: #selector(submit))
        submit.frame = NSRect(x: 20, y: y, width: 100, height: 28)
        submit.isEnabled = !Settings.shared.submitHiScoreURL.isEmpty
        cv.addSubview(submit)

        let board = NSButton(title: "Score Board", target: self, action: #selector(openBoard))
        board.frame = NSRect(x: 130, y: y, width: 120, height: 28)
        cv.addSubview(board)

        let close = NSButton(title: "Close", target: self, action: #selector(dismissDialog))
        close.frame = NSRect(x: 340, y: y, width: 100, height: 28)
        close.keyEquivalent = "\r"
        cv.addSubview(close)
    }

    @objc private func submit() {
        MainController.shared?.postHiScore(scoreString)
    }

    @objc private func openBoard() {
        if let url = URL(string: Settings.shared.webServer) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func dismissDialog() {
        // End the sheet on the parent window, then close. Using sheetParent
        // (not window?.sheetParent) is safer when the dialog is retained by
        // an external owner.
        if let parent = window?.sheetParent {
            parent.endSheet(window!)
        }
        window?.orderOut(nil)
    }
}
