//
//  MainController.swift
//  Port of Main.pas — the top-level UI controller.
//
//  Owns the main window and all controls, handles keyboard input (F1-F8, ESM,
//  RIT/speed/bandwidth hotkeys), and drives the Contest / Log / AudioEngine.
//  Conforms to SettingsSynchronizer so loaded settings can be pushed into the
//  on-screen controls, and to ScoreTableDelegate so the Log can update views.
//

import AppKit
import WebKit

public final class MainController: NSObject, NSWindowDelegate,
                                    SettingsSynchronizer, ScoreTableDelegate {

    public static var shared: MainController?

    // MARK: - main objects

    let contest: Contest
    let audioEngine = AudioEngine()
    let wavFile = WavFile()
    var histo: Histo!

    // MARK: - window & controls

    var window: NSWindow!
    // input fields
    var callField: NSTextField!
    var rstField: NSTextField!
    var nrField: NSTextField!
    var myCallField: NSTextField!
    // settings
    var wpmField: NSTextField!
    var activityField: NSTextField!
    var durationField: NSTextField!
    var pitchPopup: NSPopUpButton!
    var bandwidthPopup: NSPopUpButton!
    var qskCheckbox: NSButton!
    var qrnCheckbox: NSButton!
    var qrmCheckbox: NSButton!
    var qsbCheckbox: NSButton!
    var flutterCheckbox: NSButton!
    var lidsCheckbox: NSButton!
    var volumeSlider: NSSlider!
    // message buttons F1..F8
    var msgButtons: [NSButton] = []
    // status / clock
    var clockLabel: NSTextField!
    var modeLabel: NSTextField!
    var rateLabel: NSTextField!
    var ritView: RitIndicatorView!
    var histoView: HistogramView!
    // tables
    var qsoTableView: NSTableView!
    var qsoTableModel: QsoTableModel!
    var scoreRawLabels: [NSTextField] = []
    var scoreVerLabels: [NSTextField] = []
    // run button + menu
    var runButton: NSButton!
    var runArrowBtn: NSButton!
    var runModeMenu: NSMenu?
    var infoBar: NSTextField!
    /// Strong reference to the score dialog so its button targets (self) stay
    /// alive while the sheet is shown. Without this the controller is freed
    /// when popupScoreWpx returns, making the buttons unresponsive.
    var scoreDialog: ScoreDialog?
    // title block (shown when stopped, hidden during run)
    var titleLabels: [NSView] = []
    var logScrollView: NSScrollView?
    // menu items whose check-state must be kept in sync with Settings
    var togglesMenuItems: [NSMenuItem] = []
    var recordingMenuItem: NSMenuItem?
    var callsignInfoMenuItem: NSMenuItem?
    var themeMenuItems: [NSMenuItem] = []
    var zoomMenuItems: [NSMenuItem] = []
    /// Shared field editor for the contest input fields, so command keys reach
    /// the controller before being inserted as text.
    var fieldEditor: ContestFieldEditor?

    // MARK: - state

    public var pitchIndex: Int {
        get { pitchPopup.indexOfSelectedItem }
    }
    public var bandwidthIndex: Int {
        get { bandwidthPopup.indexOfSelectedItem }
    }
    public var selfMonValue: Float {
        get { volumeSlider.floatValue }
    }
    var mustAdvance = false

    // MARK: - lifecycle

    public override init() {
        contest = Contest()
        super.init()
        MainController.shared = self
        histo = Histo()
        buildWindow()
        audioEngine.provider = contest

        // load resources & settings
        // Seed bundled data files into ~/Library/Application Support/MorseRunner/
        // on first run so the user can find/edit/replace them.
        Settings.shared.seedUserDataIfNeeded()
        LoadCallList()
        ArrlList.shared.loadIfNeeded()
        Ini.load(into: self)
        makeKeyer()
        Keyer.rate = DEFAULTRATE
        Keyer.bufSize = Settings.shared.bufSize
        histo.setView(histoView)
        histoView.histo = histo      // back-reference so HistogramView.draw() can render
        QsoLog.shared.histo = histo
        QsoLog.shared.delegate = self
        // Apply the saved UI theme (system / light / dark).
        applyTheme(Settings.shared.theme)
        // Apply the saved zoom level (100% / 150% / 200%).
        applyZoom(Settings.shared.zoom)
    }

    public func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func saveSettings() {
        Ini.save(from: self)
    }

    // MARK: - SettingsSynchronizer

    public func setMyCall(_ call: String) {
        Settings.shared.call = call
        myCallField.stringValue = call
        Tst.me.myCall = call
    }
    public func setPitch(_ idx: Int) {
        let clamped = max(0, min(pitchPopup.numberOfItems - 1, idx))
        Settings.shared.pitch = 300 + clamped * 50
        pitchPopup.selectItem(at: clamped)
        Tst.modul.carrierFreq = Float(Settings.shared.pitch)
    }
    public func setBw(_ idx: Int) {
        guard idx >= 0, idx < bandwidthPopup.numberOfItems else { return }
        Settings.shared.bandWidth = 100 + idx * 50
        bandwidthPopup.selectItem(at: idx)
        Tst.filt.points = Int((0.7 * Float(DEFAULTRATE) / Float(Settings.shared.bandWidth)).rounded())
        Tst.filt.gainDb = 10 * log10f(500.0 / Float(Settings.shared.bandWidth))
        Tst.filt2.points = Tst.filt.points
        Tst.filt2.gainDb = Tst.filt.gainDb
        updateRitIndicator()
    }
    public func setWpm(clamping wpm: Int, lo: Int, hi: Int) {
        let v = max(lo, min(hi, wpm))
        Settings.shared.wpm = v
        wpmField.integerValue = v
        Tst.me.wpm = v
    }
    public func setQsk(_ value: Bool) {
        Settings.shared.qsk = value
        qskCheckbox.state = value ? .on : .off
    }
    public func setSelfMonVolume(raw: Int) {
        volumeSlider.floatValue = Float(raw) / 80.0 + 0.75
    }
    public func setActivity(_ value: Int) {
        Settings.shared.activity = value
        activityField.integerValue = value
    }
    public func setDuration(_ value: Int) {
        Settings.shared.duration = value
        durationField.integerValue = value
        histo.reCalc(value)
    }

    func readCheckboxes() {
        Settings.shared.qrn = qrnCheckbox.state == .on
        Settings.shared.qrm = qrmCheckbox.state == .on
        Settings.shared.qsb = qsbCheckbox.state == .on
        Settings.shared.flutter = flutterCheckbox.state == .on
        Settings.shared.lids = lidsCheckbox.state == .on
    }

    // MARK: - RIT

    func incRit(_ dF: Int) {
        switch dF {
        case -1: Settings.shared.rit -= 50
        case 0:  Settings.shared.rit = 0
        case 1:  Settings.shared.rit += 50
        default: break
        }
        Settings.shared.rit = min(500, max(-500, Settings.shared.rit))
        updateRitIndicator()
    }

    func updateRitIndicator() {
        ritView.bandWidth = Settings.shared.bandWidth
        ritView.rit = Settings.shared.rit
        ritView.needsDisplay = true
    }

    // MARK: - speed

    func incSpeed() {
        var w = Settings.shared.wpm
        w = (w / 5) * 5 + 5
        w = max(10, min(120, w))
        setWpm(clamping: w, lo: 10, hi: 120)
    }
    func decSpeed() {
        var w = Settings.shared.wpm
        w = Int((ceil(Double(w) / 5.0))) * 5 - 5
        w = max(10, min(120, w))
        setWpm(clamping: w, lo: 10, hi: 120)
    }

    // MARK: - wipe / advance

    func wipeBoxes() {
        callField.stringValue = ""
        rstField.stringValue = ""
        nrField.stringValue = ""
        window.makeFirstResponder(callField)
        QsoLog.shared.callSent = false
        QsoLog.shared.nrSent = false
    }

    /// Called (indirectly) from MyStation.getBlock() while the Contest's audio
    /// loop runs — i.e. on the realtime audio thread. ALL AppKit touches here
    /// (makeFirstResponder, stringValue=) MUST be dispatched to the main thread;
    /// doing them on the audio thread throws an Obj-C exception that terminates
    /// the app (crash on Enter after copying a call).
    func advance() {
        guard mustAdvance else { return }
        mustAdvance = false
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.rstField.stringValue.isEmpty { self.rstField.stringValue = "599" }
            if !self.callField.stringValue.contains("?") {
                self.window.makeFirstResponder(self.nrField)
            }
        }
    }

    // MARK: - sending

    func sendMsg(_ msg: StationMessage) {
        if msg == .hisCall {
            if !callField.stringValue.isEmpty {
                Tst.me.hisCall = callField.stringValue
            }
            QsoLog.shared.callSent = true
        }
        if msg == .nr {
            QsoLog.shared.nrSent = true
        }
        Tst.me.sendMsg(msg)
    }

    /// ESM (Enter Sends Messages) — faithful port of Main.pas ProcessEnter.
    /// `modifiers` carries the key event's modifier flags so the "Ctrl/Shift/Alt +
    /// Enter = save" shortcut can be detected (the original reads GetKeyState).
    func processEnter(modifiers: NSEvent.ModifierFlags = []) {
        mustAdvance = false

        // Ctrl/Shift/Alt + Enter → just save the QSO.
        let saveMods: NSEvent.ModifierFlags = [.control, .shift, .option, .command]
        if !modifiers.intersection(saveMods).isEmpty {
            saveQso()
            return
        }

        // No QSO in progress → send CQ.
        if callField.stringValue.isEmpty {
            sendMsg(.cq)
            return
        }

        let c = QsoLog.shared.callSent
        let n = QsoLog.shared.nrSent
        let r = !nrField.stringValue.isEmpty

        // Send his call if not sent before, or if call changed.
        if (!c) || ((!n) && (!r)) { sendMsg(.hisCall) }
        if !n { sendMsg(.nr) }
        if n && !r { sendMsg(.qm) }

        if r && (c || n) {
            sendMsg(.tu)
            saveQso()
        } else {
            mustAdvance = true
        }
    }

    func saveQso() {
        QsoLog.shared.saveQso(callField: callField.stringValue,
                              rstField: rstField.stringValue,
                              nrField: nrField.stringValue)
    }

    // MARK: - Run modes

    public func run(_ value: RunMode) {
        if value == Settings.shared.runMode { return }
        let bStop = value == .stop
        let bCompet = value == .wpx || value == .hst
        Settings.shared.runMode = value

        myCallField.isEnabled = bStop
        durationField.isEnabled = bStop
        for cb in [qrnCheckbox, qrmCheckbox, qsbCheckbox, flutterCheckbox, lidsCheckbox] {
            cb?.isEnabled = !bCompet
        }
        if value == .wpx {
            qrnCheckbox.state = .on; qrmCheckbox.state = .on
            qsbCheckbox.state = .on; flutterCheckbox.state = .on; lidsCheckbox.state = .on
            // Use the competition duration AND sync Settings.shared.duration so
            // the countdown clock and the actual session length agree (the
            // original Delphi set SpinEdit2.Value which fired its OnChange →
            // Ini.Duration; here we update both the field and the setting).
            durationField.integerValue = Settings.shared.compDuration
            Settings.shared.duration = Settings.shared.compDuration
            histo.reCalc(Settings.shared.duration)
            readCheckboxes()
        } else if value == .hst {
            qrnCheckbox.state = .off; qrmCheckbox.state = .off
            qsbCheckbox.state = .off; flutterCheckbox.state = .off; lidsCheckbox.state = .off
            durationField.integerValue = Settings.shared.compDuration
            Settings.shared.duration = Settings.shared.compDuration
            histo.reCalc(Settings.shared.duration)
            readCheckboxes()
        }
        activityField.isEnabled = value != .hst
        if value == .hst {
            activityField.integerValue = 4
            Settings.shared.activity = 4
            bandwidthPopup.isEnabled = false
            setBw(10)
        } else if value != .stop {
            bandwidthPopup.isEnabled = true
        }

        let title: String
        switch value {
        case .stop: title = ""
        case .pileUp: title = "Pile-Up"
        case .single: title = "Single Calls"
        case .wpx: title = "COMPETITION"
        case .hst: title = "H S T"
        }
        modeLabel.stringValue = title
        modeLabel.textColor = bCompet ? .systemRed : .systemGreen

        // Run button reflects state: "Run" when stopped, "Stop" when running
        // (so a second click stops, matching the original ToolButton1 toggle).
        runButton.title = bStop ? "Run" : "Stop"
        runArrowBtn.isEnabled = true

        if !bStop {
            // Fresh start: clear the simulation, stations, log, and all
            // "session ending" latches so re-running is NOT a resume.
            // (Original Run() does BlockNumber:=0 + Log.Clear + WipeBoxes.)
            Tst.initContest()
            Tst.me.abortSend()
            Tst.me.nr = 1
            Tst.fStopPressed = false
            Tst.sessionEnding = false
            QsoLog.shared.clear()
            wipeBoxes()
            incRit(0)
            // Hide the title block and let the QSO log fill the left area.
            titleLabels.forEach { $0.isHidden = true }
            logScrollView?.isHidden = false
            infoBar.isHidden = !Settings.shared.showCallsignInfo
        } else {
            // Restore the title screen when stopped.
            titleLabels.forEach { $0.isHidden = false }
        }

        // WAV recording
        if bStop {
            if wavFile.isOpen { wavFile.close() }
        } else {
            wavFile.fileName = FileManager.default.applicationSupportDirectory
                .appendingPathComponent("MorseRunner.wav").path
            if Settings.shared.saveWav { wavFile.openWrite() }
        }
        audioEngine.enabled = !bStop
    }

    // MARK: - score popups

    public func popupScoreWpx() {
        guard !qsoListCopy().isEmpty else { return }
        let pts = Int(scoreRawLabels[2].stringValue) ?? 0
        let raw = "\(scoreRawLabels[0].stringValue) \(scoreRawLabels[1].stringValue)"
        let ver = "\(scoreVerLabels[0].stringValue) \(scoreVerLabels[1].stringValue)"
        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
        var s = "\(dateStr) \(Settings.shared.call) \(raw) \(ver) "
        s += "[\(String(format: "%08X", calculateCRC32(s, seed: 0xC90C2086)))]"

        // append to score table file
        let url = FileManager.default.applicationSupportDirectory
            .appendingPathComponent("MorseRunner.lst")
        var lines: [String] = []
        if let existing = try? String(contentsOf: url) {
            lines = existing.split(separator: "\n").map(String.init)
        }
        lines.append(s)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)

        let isHi = pts > Settings.shared.hiScore
        Settings.shared.hiScore = max(Settings.shared.hiScore, pts)
        let dlg = ScoreDialog(scoreString: s, isHiScore: isHi)
        // Keep a strong reference so the dialog (and its button targets) stay
        // alive while the sheet is presented. Cleared in dismissScoreDialog.
        scoreDialog = dlg
        window.beginSheet(dlg.window!) { [weak self] _ in
            self?.scoreDialog = nil
        }
    }

    public func popupScoreHst() {
        let dateStr = ISO8601DateFormatter().string(from: Date())
        let s = "\(dateStr)\t\(Settings.shared.call)\t\(Settings.shared.hamName)\t\(scoreVerLabels[2].stringValue)"
        let url = FileManager.default.applicationSupportDirectory
            .appendingPathComponent("HstResults.txt")
        var lines: [String] = []
        if let existing = try? String(contentsOf: url) {
            lines = existing.split(separator: "\n").map(String.init)
        }
        lines.append(s)
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        let alert = NSAlert()
        alert.messageText = "HST Score: \(scoreVerLabels[2].stringValue)"
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in }
    }

    public func postHiScore(_ score: String) {
        guard !Settings.shared.submitHiScoreURL.isEmpty else { return }
        let urlStr = String(format: Settings.shared.submitHiScoreURL, score)
            .replacingOccurrences(of: " ", with: "%20")
        guard let url = URL(string: urlStr) else { return }
        let method = Settings.shared.postMethod == "POST" ? "POST" : "GET"
        var req = URLRequest(url: url)
        req.httpMethod = method
        if method == "POST" {
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        let task = URLSession.shared.dataTask(with: req) { [weak self] _, response, _ in
            DispatchQueue.main.async {
                let ok = (response as? HTTPURLResponse)?.statusCode ?? 0
                self?.showAlert(ok != 0 ? "Sent!" : "Error!")
            }
        }
        task.resume()
    }

    private func showAlert(_ text: String) {
        let a = NSAlert(); a.messageText = text; a.addButton(withTitle: "OK")
        a.beginSheetModal(for: window) { _ in }
    }

    public func updateRunningDisplay(timeText: String, pileUpCount: Int, isPileUp: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.clockLabel.stringValue = timeText
            if isPileUp {
                self?.modeLabel.stringValue = "Pile-Up:  \(pileUpCount)"
            }
        }
    }

    // MARK: - ScoreTableDelegate
    // NOTE: these are invoked from the realtime Core Audio render thread
    // (Contest.getAudio). Every AppKit touch MUST be dispatched to the main
    // thread — touching NSView/NSTableView/NSControl from the audio thread is
    // undefined behaviour and was the cause of the crash on "Run".

    public func scoreTableSetTitle(_ c1: String, _ c2: String, _ c3: String, _ c4: String, _ c5: String, _ c6: String) {
        let titles = [c1, c2, c3, c4, c5, c6]
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let cols = self.qsoTableView.tableColumns
            for (i, col) in cols.enumerated() where i < titles.count {
                col.title = titles[i]
            }
        }
    }
    public func scoreTableInsert(_ c1: String, _ c2: String, _ c3: String, _ c4: String, _ c5: String, _ c6: String) {
        let row = [c1, c2, c3, c4, c5, c6]
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.qsoTableModel.appendRow(row)
            self.qsoTableView.reloadData()
            let lastRow = self.qsoTableModel.numberOfRows(in: self.qsoTableView) - 1
            if lastRow >= 0 {
                self.qsoTableView.scrollRowToVisible(lastRow)
                self.qsoTableView.selectRowIndexes(IndexSet(integer: lastRow), byExtendingSelection: false)
            }
        }
    }
    public func scoreTableClear() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.qsoTableModel.clear()
            self.qsoTableView.reloadData()
            // Also clear the callsign-info bar so a fresh run doesn't show
            // the previous QSO's DXCC info.
            self.infoBar.stringValue = ""
        }
    }
    public func scoreTableUpdateLastError(_ err: String) {
        DispatchQueue.main.async { [weak self] in
            self?.qsoTableModel.updateLastError(err)
            self?.qsoTableView.reloadData()
        }
    }
    public func scoreTableUpdateRowError(_ row: Int, _ err: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.qsoTableModel.updateRowError(row, err)
            // Reload just the affected row's cells for a flicker-free update.
            let indices = IndexSet(integer: row)
            self.qsoTableView.reloadData(forRowIndexes: indices, columnIndexes: IndexSet(integer: 5))
        }
    }
    public func scoreViewSetNeedsDisplay() {
        // Recompute the histogram counts from the QSO log, then redraw.
        // (repaint() updates Histo.counts from QsoLog and flips needsDisplay;
        //  without it the bars never update — they always show zero.)
        DispatchQueue.main.async { [weak self] in
            self?.histo?.repaint()   // recomputes counts + sets needsDisplay
            self?.histoView.needsDisplay = true
        }
    }
    public func setRawScore(_ idx: Int, value: String) {
        DispatchQueue.main.async { [weak self] in
            if idx < (self?.scoreRawLabels.count ?? 0) { self?.scoreRawLabels[idx].stringValue = value }
        }
    }
    public func setVerifiedScore(_ idx: Int, value: String) {
        DispatchQueue.main.async { [weak self] in
            if idx < (self?.scoreVerLabels.count ?? 0) { self?.scoreVerLabels[idx].stringValue = value }
        }
    }
    public func setRateText(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.rateLabel.stringValue = text }
    }
    public func setRunClockText(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.clockLabel.stringValue = text }
    }
    public func setPileUpCount(_ count: Int, isPileUp: Bool) {
        DispatchQueue.main.async { [weak self] in
            if isPileUp { self?.modeLabel.stringValue = "Pile-Up:  \(count)" }
        }
    }
    public func setInfoBar(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.infoBar.stringValue = text }
    }

    /// Update the callsign-info bar for a table selection. When `row` is nil
    /// (no selection), fall back to the most-recent QSO so that during an
    /// active contest the latest contact's info stays visible. Mirrors the
    /// original ListView2SelectItem → UpdateSbar(Item.SubItems[0]).
    func updateInfoBarForSelection(_ row: Int?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Column 1 is the Call column in the log table.
            let call: String
            if let r = row, r >= 0, r < self.qsoTableModel.rows.count,
               self.qsoTableModel.rows[r].count > 1 {
                call = self.qsoTableModel.rows[r][1]
            } else {
                // No selection → latest QSO's call (if any).
                call = QsoLog.shared.qsoList.last?.call ?? ""
            }
            guard !call.isEmpty else { self.infoBar.stringValue = ""; return }
            let info = ArrlList.shared.search(call)
            self.infoBar.stringValue = info.isEmpty ? "  \(call)  Unknown" : "  \(info)"
        }
    }

    // helper used by popupScoreWpx
    private func qsoListCopy() -> [Qso] { return QsoLog.shared.qsoList }
}
