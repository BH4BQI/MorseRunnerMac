//
//  MainController+Build.swift
//  Window construction + keyboard/menu wiring (port of Main.dfm + Main.pas events).
//

import AppKit

extension MainController {

    func buildWindow() {
        // Original layout (Main.dfm): window 729×469. Fixed at the design size
        // (730×470) — no resizing. Layout regions (in design coords):
        //   Panel6  (0,2 .. 517×322): left main area — title + QSO log.
        //   Panel9  (517,2 .. 212×322): right column — Station / Band / Run.
        //   Panel1  (0,334 .. 729×135): bottom strip — Call/RST/NR + F1..F8 +
        //                             clock/mode/rate + histogram + score.
        let frame = NSRect(x: 0, y: 0, width: 730, height: 470)
        window = MainWindowClass(contentRect: frame,
                          styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "Morse Runner \(sVersion)"
        window.delegate = self
        window.isReleasedWhenClosed = false
        // Explicit background colour so the window (incl. title bar area)
        // matches the active theme instead of falling back to opaque black.
        window.backgroundColor = .windowBackgroundColor
        window.center()
        // Lock to the fixed design size.
        window.styleMask.remove(.resizable)
        window.minSize = frame.size
        window.maxSize = frame.size

        // Replace the default (bottom-left-origin) contentView with a flipped
        // one so all region containers can be placed with DFM top-left coords:
        // Top=0 is the window's top, Top=335 is near the bottom. This is what
        // makes "bottom strip at y=335" actually render at the bottom.
        let flipped = FlippedContentView()
        window.contentView = flipped
        // Note: do NOT set wantsLayer on the content view — a layer-backed view
        // with no explicit background draws opaque black, which shows through
        // the transparent group boxes. The content view's draw() fills with
        // windowBackgroundColor instead.

        buildMenuBar()

        // All UI is added to the flipped content view in design coords.
        let canvas = flipped

        // Helper to place a subview at top-left coordinates (DFM-style) within
        // a parent whose origin is top-left.
        func place(_ view: NSView, in parent: NSView, left: CGFloat, top: CGFloat, w: CGFloat, h: CGFloat) {
            view.frame = NSRect(x: left, y: top, width: w, height: h)
            parent.addSubview(view)
        }

        // ============================================================
        // RIGHT COLUMN — Station / Band Conditions / Run  (Panel9)
        // ============================================================
        let rightCol = FlippedView(frame: NSRect(x: 515, y: 2, width: 210, height: 320))
        canvas.addSubview(rightCol)

        // --- Station group box ---
        // Use .custom so the box draws NO border/fill of its own (the default
        // .primary border renders black in some configurations). We draw the
        // title caption separately and rely on the system box chrome elsewhere.
        let stationBox = makeGroupBox(frame: NSRect(x: 8, y: 6, width: 194, height: 163))
        rightCol.addSubview(stationBox)
        // header label overlaps the box's top border (matches DFM group caption).
        // rightCol is flipped, so y is from the top; stationBox top is at y=6.
        let stationTitle = groupHeaderLabel("Station")
        stationTitle.frame = NSRect(x: 16, y: 0, width: 80, height: 14)
        rightCol.addSubview(stationTitle)

        // Call label + field + QSK checkbox (row 1)
        place(NSTextField(labelWithString: "Call").withFont(.systemFont(ofSize: 10)),
              in: stationBox.contentView!, left: 12, top: 26, w: 30, h: 15)
        myCallField = NSTextField(string: "VE3NEA")
        myCallField.font = .systemFont(ofSize: 11)
        myCallField.formatter = UpperCaseFormatter()
        myCallField.frame = NSRect(x: 43, y: 22, width: 89, height: 23)
        myCallField.action = #selector(myCallChanged); myCallField.target = self
        stationBox.contentView!.addSubview(myCallField)
        qskCheckbox = NSButton(checkboxWithTitle: "QSK", target: self, action: #selector(qskChanged))
        qskCheckbox.frame = NSRect(x: 140, y: 24, width: 50, height: 17)
        stationBox.contentView!.addSubview(qskCheckbox)

        // CW Speed (row 2)
        place(NSTextField(labelWithString: "CW Speed").withFont(.systemFont(ofSize: 10)),
              in: stationBox.contentView!, left: 12, top: 54, w: 60, h: 15)
        place(NSTextField(labelWithString: "WPM").withFont(.systemFont(ofSize: 10)),
              in: stationBox.contentView!, left: 156, top: 54, w: 30, h: 15)
        wpmField = NSTextField(string: "35")
        wpmField.font = .systemFont(ofSize: 11)
        wpmField.formatter = DigitsOnlyFormatter(maxLength: 3)
        wpmField.frame = NSRect(x: 88, y: 50, width: 65, height: 24)
        wpmField.action = #selector(wpmChanged); wpmField.target = self
        stationBox.contentView!.addSubview(wpmField)

        // CW Pitch (row 3)
        place(NSTextField(labelWithString: "CW Pitch").withFont(.systemFont(ofSize: 10)),
              in: stationBox.contentView!, left: 12, top: 82, w: 60, h: 15)
        pitchPopup = NSPopUpButton(frame: NSRect(x: 88, y: 78, width: 65, height: 23), pullsDown: false)
        pitchPopup.addItems(withTitles: pitchItems())
        pitchPopup.action = #selector(pitchChanged); pitchPopup.target = self
        stationBox.contentView!.addSubview(pitchPopup)

        // RX Bandwidth (row 4)
        place(NSTextField(labelWithString: "RX Bandwidth").withFont(.systemFont(ofSize: 10)),
              in: stationBox.contentView!, left: 12, top: 110, w: 75, h: 15)
        bandwidthPopup = NSPopUpButton(frame: NSRect(x: 88, y: 106, width: 65, height: 23), pullsDown: false)
        bandwidthPopup.addItems(withTitles: bandwidthItems())
        bandwidthPopup.action = #selector(bandwidthChanged); bandwidthPopup.target = self
        stationBox.contentView!.addSubview(bandwidthPopup)

        // Mon. Level label + slider (row 5)
        place(NSTextField(labelWithString: "Mon. Level").withFont(.systemFont(ofSize: 10)),
              in: stationBox.contentView!, left: 12, top: 140, w: 70, h: 15)
        volumeSlider = NSSlider(value: 0.75, minValue: 0, maxValue: 1, target: self,
                                action: #selector(volumeChanged))
        volumeSlider.frame = NSRect(x: 89, y: 138, width: 95, height: 20)
        stationBox.contentView!.addSubview(volumeSlider)

        // --- Band Conditions group box ---
        // Station box bottom is at y=6+163=169; leave a clear gap below it so
        // the two boxes don't touch (was y=171, only 2px apart).
        let bandBox = makeGroupBox(frame: NSRect(x: 8, y: 179, width: 194, height: 87))
        rightCol.addSubview(bandBox)
        let bandHdr = groupHeaderLabel("Band Conditions")
        bandHdr.frame = NSRect(x: 16, y: 173, width: 120, height: 14)
        rightCol.addSubview(bandHdr)

        // Band Conditions checkboxes — 2 columns, compact 11pt font to match the
        // original 8pt MS Sans Serif look. Widths sized so no caption is clipped.
        let bandFont = NSFont.systemFont(ofSize: 11)
        qrnCheckbox = NSButton(checkboxWithTitle: "QRN", target: self, action: #selector(checkboxChanged))
        qrnCheckbox.font = bandFont
        qrnCheckbox.frame = NSRect(x: 12, y: 21, width: 55, height: 17); bandBox.contentView!.addSubview(qrnCheckbox)
        flutterCheckbox = NSButton(checkboxWithTitle: "Flutter", target: self, action: #selector(checkboxChanged))
        flutterCheckbox.font = bandFont
        flutterCheckbox.frame = NSRect(x: 76, y: 21, width: 62, height: 17); bandBox.contentView!.addSubview(flutterCheckbox)
        place(NSTextField(labelWithString: "Activity").withFont(.systemFont(ofSize: 10)),
              in: bandBox.contentView!, left: 144, top: 19, w: 50, h: 15)
        activityField = NSTextField(string: "5")
        activityField.font = .systemFont(ofSize: 11)
        activityField.formatter = DigitsOnlyFormatter(maxLength: 2)
        activityField.alignment = .center
        activityField.frame = NSRect(x: 144, y: 35, width: 37, height: 24)
        activityField.action = #selector(activityChanged); activityField.target = self
        bandBox.contentView!.addSubview(activityField)

        qrmCheckbox = NSButton(checkboxWithTitle: "QRM", target: self, action: #selector(checkboxChanged))
        qrmCheckbox.font = bandFont
        qrmCheckbox.frame = NSRect(x: 12, y: 41, width: 55, height: 17); bandBox.contentView!.addSubview(qrmCheckbox)
        lidsCheckbox = NSButton(checkboxWithTitle: "LID's", target: self, action: #selector(checkboxChanged))
        lidsCheckbox.font = bandFont
        lidsCheckbox.frame = NSRect(x: 76, y: 43, width: 55, height: 17); bandBox.contentView!.addSubview(lidsCheckbox)
        qsbCheckbox = NSButton(checkboxWithTitle: "QSB", target: self, action: #selector(checkboxChanged))
        qsbCheckbox.font = bandFont
        qsbCheckbox.frame = NSRect(x: 12, y: 61, width: 55, height: 17); bandBox.contentView!.addSubview(qsbCheckbox)

        // --- Run row panel (Panel10) ---
        // The original ToolButton1 is a tbsDropDown: clicking the body toggles
        // Run/Stop; the arrow opens a menu of run modes. We replicate that with
        // a split button — a toggle button + a small arrow button side by side.
        let runRow = FlippedView(frame: NSRect(x: 0, y: 285, width: 210, height: 37))
        rightCol.addSubview(runRow)
        runButton = NSButton(title: "Run", target: self, action: #selector(runClicked))
        runButton.bezelStyle = .rounded
        runButton.frame = NSRect(x: 6, y: 6, width: 80, height: 27)
        runRow.addSubview(runButton)
        runArrowBtn = NSButton(image: NSImage(named: NSImage.touchBarGoDownTemplateName) ??
                                    NSImage(named: NSImage.goForwardTemplateName)!,
                               target: self, action: #selector(showRunMenu))
        runArrowBtn.bezelStyle = .rounded
        runArrowBtn.imagePosition = .imageOnly
        runArrowBtn.frame = NSRect(x: 86, y: 6, width: 20, height: 27)
        runRow.addSubview(runArrowBtn)
        buildRunDropdownMenu()
        place(NSTextField(labelWithString: "for").withFont(.systemFont(ofSize: 10)),
              in: runRow, left: 109, top: 11, w: 15, h: 15)
        durationField = NSTextField(string: "30")
        durationField.font = .systemFont(ofSize: 11)
        durationField.formatter = DigitsOnlyFormatter(maxLength: 3)
        durationField.alignment = .center
        durationField.frame = NSRect(x: 128, y: 8, width: 45, height: 24)
        durationField.action = #selector(durationChanged); durationField.target = self
        runRow.addSubview(durationField)
        place(NSTextField(labelWithString: "min.").withFont(.systemFont(ofSize: 10)),
              in: runRow, left: 179, top: 11, w: 25, h: 15)

        // ============================================================
        // LEFT MAIN AREA — title + QSO log + RIT bar + info bar (Panel6)
        // ============================================================
        let leftMain = FlippedView(frame: NSRect(x: 4, y: 2, width: 511, height: 320))
        canvas.addSubview(leftMain)

        // Title block (only shown when stopped; hidden during run via Run()).
        let titleBox = NSTextField(labelWithString: "Morse Runner \(sVersion)")
        titleBox.font = .systemFont(ofSize: 28, weight: .bold)
        titleBox.textColor = .windowFrameTextColor
        titleBox.frame = NSRect(x: 70, y: 60, width: 380, height: 40)
        leftMain.addSubview(titleBox)
        let copyLine = NSTextField(labelWithString: "Copyright ©2004-2016 Alex Shovkoplyas, VE3NEA")
        copyLine.font = .systemFont(ofSize: 11)
        copyLine.frame = NSRect(x: 70, y: 105, width: 380, height: 15)
        leftMain.addSubview(copyLine)
        let freeLine = NSTextField(labelWithString: "FREEWARE")
        freeLine.font = .systemFont(ofSize: 11)
        freeLine.alignment = .center
        freeLine.frame = NSRect(x: 70, y: 124, width: 380, height: 15)
        leftMain.addSubview(freeLine)
        self.titleLabels = [titleBox, copyLine, freeLine]

        // QSO log table — fills the left region from the top down to just above
        // the callsign-info bar. When stopped the title block overlays it; when
        // running the title is hidden and the log fills the whole space.
        qsoTableView = NSTableView()
        qsoTableModel = QsoTableModel()
        qsoTableView.dataSource = qsoTableModel
        qsoTableView.delegate = qsoTableModel
        // Don't let the table auto-resize columns (it would hide the Chk column
        // when the total width exceeds the scroll view). We size them ourselves.
        qsoTableView.columnAutoresizingStyle = .noColumnAutoresizing
        // Column widths are deliberately compact so the total (~440px) leaves
        // room for the vertical scrollbar AND keeps the Chk column visible by
        // default within the ~490px content width (leftMain 511 minus padding).
        let logColumns: [(String, CGFloat)] = [("UTC", 70), ("Call", 84), ("Recv", 78), ("Sent", 74), ("Pref", 50), ("Chk", 52)]
        for (name, w) in logColumns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
            col.title = name
            col.width = w
            qsoTableView.addTableColumn(col)
        }
        let logScroll = NSScrollView()
        logScroll.documentView = qsoTableView
        logScroll.hasVerticalScroller = true
        logScroll.autohidesScrollers = false
        logScroll.autoresizingMask = [.width, .height]
        // Reserve 20px at the bottom for the info bar; the log fills the rest.
        // (leftMain height = 320; infoBar is 18px tall pinned to the bottom.)
        let infoBarH: CGFloat = 18
        let logH: CGFloat = 320 - infoBarH - 2
        logScroll.frame = NSRect(x: 0, y: 0, width: 511, height: logH)
        leftMain.addSubview(logScroll)
        self.logScrollView = logScroll

        // When the user selects a row in the QSO log, show that QSO's callsign
        // info in the info bar (mirrors the original ListView2SelectItem →
        // UpdateSbar). When the selection is cleared, fall back to the latest.
        qsoTableModel.onSelectionChange = { [weak self] row in
            self?.updateInfoBarForSelection(row)
        }

        // Info bar (callsign info / sbar) — pinned to the bottom of the left
        // region, just above the bottom strip, so it hugs the operating area.
        infoBar = NSTextField(labelWithString: "")
        infoBar.font = .systemFont(ofSize: 11)
        infoBar.frame = NSRect(x: 4, y: 320 - infoBarH, width: 503, height: infoBarH)
        leftMain.addSubview(infoBar)

        // Score-table rich text (View Score Table) — bottom strip of left panel.
        // Reuse infoBar area is reserved; we don't replicate RichEdit1 here as a
        // separate control — the score table is shown via the QSO log view modes.

        // ============================================================
        // BOTTOM STRIP — Call/RST/NR + F1..F8 (left) ; clock/mode/rate +
        //                histogram + score columns (right)   (Panel1)
        // ============================================================
        // Bottom strip — full original height 135 (335..470).
        let bottom = FlippedView(frame: NSRect(x: 0, y: 335, width: 730, height: 135))
        canvas.addSubview(bottom)

        // --- left half of bottom strip: input fields + F-keys ---
        // Call / RST / Nr. labels + fields
        place(NSTextField(labelWithString: "Call").withFont(.systemFont(ofSize: 10)),
              in: bottom, left: 16, top: 12, w: 30, h: 15)
        callField = NSTextField(string: "")
        callField.font = .systemFont(ofSize: 14)
        callField.alignment = .center
        callField.formatter = UpperCaseFormatter()
        callField.placeholderString = "callsign"
        callField.frame = NSRect(x: 12, y: 28, width: 149, height: 27)
        callField.delegate = self
        bottom.addSubview(callField)

        place(NSTextField(labelWithString: "RST").withFont(.systemFont(ofSize: 10)),
              in: bottom, left: 172, top: 12, w: 30, h: 15)
        rstField = NSTextField(string: "")
        rstField.font = .systemFont(ofSize: 14)
        rstField.alignment = .center
        rstField.formatter = DigitsOnlyFormatter(maxLength: 3)
        rstField.placeholderString = "599"
        rstField.frame = NSRect(x: 168, y: 28, width: 45, height: 27)
        rstField.delegate = self
        bottom.addSubview(rstField)

        place(NSTextField(labelWithString: "Nr.").withFont(.systemFont(ofSize: 10)),
              in: bottom, left: 224, top: 12, w: 24, h: 15)
        nrField = NSTextField(string: "")
        nrField.font = .systemFont(ofSize: 14)
        nrField.alignment = .center
        nrField.formatter = DigitsOnlyFormatter(maxLength: 6)
        nrField.placeholderString = "nr"
        nrField.frame = NSRect(x: 220, y: 28, width: 45, height: 27)
        nrField.delegate = self
        bottom.addSubview(nrField)

        // Make Tab cycle through the three contest fields (Call → RST → NR →
        // Call). This is a belt-and-suspenders alongside doCommandBy: insertTab;
        // it also ensures the Tab key works even when focus arrived via mouse.
        callField.nextKeyView = rstField
        rstField.nextKeyView = nrField
        nrField.nextKeyView = callField

        // Vertical divider between the F-key block and the clock block.
        let divider = NSBox(frame: NSRect(x: 277, y: 6, width: 2, height: 123))
        divider.boxType = .separator
        bottom.addSubview(divider)

        // F1..F8 message buttons (2 rows × 4), matching the DFM captions.
        // DFM: F1 CQ, F2 <#>, F3 TU, F4 <my>, F5 <his>, F6 B4, F7 ?, F8 NIL
        let messages: [(String, StationMessage)] = [
            ("F1  CQ", .cq), ("F2  <#>", .nr), ("F3  TU", .tu), ("F4  <my>", .myCall),
            ("F5  <his>", .hisCall), ("F6  B4", .b4), ("F7  ?", .qm), ("F8  NIL", .nilMsg),
        ]
        let btnW: CGFloat = 61, btnH: CGFloat = 26
        for (i, (cap, msg)) in messages.enumerated() {
            let col = i % 4, row = i / 4
            let btn = NSButton(title: cap, target: self, action: #selector(msgClicked(_:)))
            btn.tag = msg.rawValue
            btn.bezelStyle = .rounded
            btn.font = .systemFont(ofSize: 10)
            btn.frame = NSRect(x: 12 + CGFloat(col) * 64, y: 66 + CGFloat(row) * 28, width: btnW, height: btnH)
            bottom.addSubview(btn)
            msgButtons.append(btn)
        }

        // --- right half of bottom strip: clock/mode/rate + RIT bar + histogram + score ---
        // Clock (Panel2) at top-right.
        clockLabel = NSTextField(labelWithString: "00:00:00")
        clockLabel.alignment = .center
        clockLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        clockLabel.frame = NSRect(x: 529, y: 6, width: 191, height: 33)
        bottom.addSubview(clockLabel)

        // Mode label (Panel4) and rate label (Panel7).
        modeLabel = NSTextField(labelWithString: "")
        modeLabel.alignment = .center
        modeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        modeLabel.frame = NSRect(x: 292, y: 6, width: 114, height: 33)
        bottom.addSubview(modeLabel)

        rateLabel = NSTextField(labelWithString: "0 q/h")
        rateLabel.alignment = .center
        rateLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        rateLabel.frame = NSRect(x: 412, y: 6, width: 104, height: 33)
        bottom.addSubview(rateLabel)

        // Histogram (Panel3 + PaintBox1) below the mode/rate row.
        histoView = HistogramView(frame: NSRect(x: 292, y: 45, width: 225, height: 67))
        bottom.addSubview(histoView)

        // RIT indicator bar (Panel8 + Shape2) just under the histogram.
        ritView = RitIndicatorView(frame: NSRect(x: 292, y: 119, width: 225, height: 10))
        bottom.addSubview(ritView)

        // Score columns (Panel11 + ListView1) — Raw / Verified, 3 rows.
        let scoreBox = NSBox(frame: NSRect(x: 529, y: 44, width: 191, height: 85))
        scoreBox.titlePosition = .noTitle
        scoreBox.contentView = FlippedView(frame: NSRect(x: 0, y: 0, width: 189, height: 83))
        bottom.addSubview(scoreBox)
        // two column headers + three row labels
        let rawHdr = NSTextField(labelWithString: "Raw")
        rawHdr.font = .systemFont(ofSize: 9); rawHdr.alignment = .center
        rawHdr.frame = NSRect(x: 4, y: 4, width: 90, height: 12); scoreBox.contentView!.addSubview(rawHdr)
        let verHdr = NSTextField(labelWithString: "Verified")
        verHdr.font = .systemFont(ofSize: 9); verHdr.alignment = .center
        verHdr.frame = NSRect(x: 96, y: 4, width: 90, height: 12); scoreBox.contentView!.addSubview(verHdr)
        let rowNames = ["QSOs", "Mult", "Score"]
        for (i, name) in rowNames.enumerated() {
            let y = 18 + CGFloat(i) * 20
            let nm = NSTextField(labelWithString: name)
            nm.font = .systemFont(ofSize: 9); nm.alignment = .right
            nm.frame = NSRect(x: 2, y: y + 2, width: 38, height: 12)
            scoreBox.contentView!.addSubview(nm)
            let raw = NSTextField(labelWithString: "0")
            raw.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            raw.alignment = .right
            raw.frame = NSRect(x: 42, y: y, width: 48, height: 14)
            scoreBox.contentView!.addSubview(raw)
            scoreRawLabels.append(raw)
            let ver = NSTextField(labelWithString: "0")
            ver.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            ver.alignment = .right
            ver.frame = NSRect(x: 134, y: y, width: 48, height: 14)
            scoreBox.contentView!.addSubview(ver)
            scoreVerLabels.append(ver)
        }
    }

    // Outlets built in buildWindow that are also referenced by run(); declared
    // as instance properties on the main class (extensions can't store state).
    /// Build a group box with a flipped contentView (top-left origin) so DFM
    /// Top= coordinates place child controls correctly. Uses .custom boxType so
    /// no legacy border/fill is drawn (the default .primary border renders
    /// black in light mode); the box shows only a thin separator border.
    fileprivate func makeGroupBox(frame: NSRect) -> NSBox {
        let box = NSBox(frame: frame)
        box.titlePosition = .noTitle
        box.boxType = .custom
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.fillColor = .clear
        box.contentView = FlippedView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
        return box
    }

    fileprivate func groupHeaderLabel(_ title: String) -> NSTextField {
        let lbl = NSTextField(labelWithString: " \(title) ")
        lbl.font = .systemFont(ofSize: 10, weight: .semibold)
        lbl.textColor = .secondaryLabelColor
        // Transparent background so the label always matches the current theme
        // (light/dark). A fixed layer.backgroundColor would not update on theme
        // switch and could render as black in light mode.
        lbl.drawsBackground = false
        lbl.isBezeled = false
        lbl.isBordered = false
        lbl.sizeToFit()
        return lbl
    }

    // MARK: - helpers

    private func pitchItems() -> [String] {
        return (0..<14).map { String(300 + $0 * 50) }
    }
    private func bandwidthItems() -> [String] {
        return (0..<17).map { String(100 + $0 * 50) }
    }

    // MARK: - control actions

    @objc func myCallChanged() { setMyCall(myCallField.stringValue.trimmingCharacters(in: .whitespaces)) }
    @objc func wpmChanged() { setWpm(clamping: wpmField.integerValue, lo: 10, hi: 120) }
    @objc func pitchChanged() { setPitch(pitchPopup.indexOfSelectedItem) }
    @objc func bandwidthChanged() { setBw(bandwidthPopup.indexOfSelectedItem) }
    @objc func qskChanged() {
        Settings.shared.qsk = qskCheckbox.state == .on
        window.makeFirstResponder(callField)
    }
    @objc func checkboxChanged() {
        readCheckboxes()
        refreshMenuStates()
        window.makeFirstResponder(callField)
    }
    @objc func activityChanged() { Settings.shared.activity = activityField.integerValue }
    @objc func durationChanged() {
        Settings.shared.duration = durationField.integerValue
        histo.reCalc(durationField.integerValue)
    }
    @objc func volumeChanged() {
        Settings.shared.selfMonVolume = volumeSlider.floatValue
    }
    @objc func msgClicked(_ sender: NSButton) {
        guard let msg = StationMessage(rawValue: sender.tag) else { return }
        sendMsg(msg)
    }
    @objc func runClicked() {
        // Toggle body: starts Pile-Up when stopped, stops when running.
        // (Mirrors the original RunBtnClick.)
        if Settings.shared.runMode == .stop {
            run(.pileUp)
        } else {
            Tst.fStopPressed = true
        }
    }

    /// Build the dropdown menu: Pile-Up / Single Calls / WPX / HST / Stop.
    /// Tag = TRunMode raw value, matching the original RunMNUClick.
    private func buildRunDropdownMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let modes: [(String, RunMode, Bool)] = [
            ("Pile-Up", .pileUp, true),
            ("Single Calls", .single, false),
            ("WPX Competition", .wpx, false),
            ("HST Competition", .hst, false),
        ]
        for (title, mode, isDefault) in modes {
            let item = NSMenuItem(title: title, action: #selector(runMenuClicked(_:)),
                                   keyEquivalent: "")
            item.tag = mode.rawValue
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let stopItem = NSMenuItem(title: "Stop", action: #selector(runMenuClicked(_:)),
                                  keyEquivalent: "")
        stopItem.tag = RunMode.stop.rawValue
        stopItem.target = self
        menu.addItem(stopItem)
        runModeMenu = menu
    }

    /// Show the dropdown under the arrow button.
    @objc func showRunMenu() {
        guard let menu = runModeMenu else { return }
        // Enable/disable per current state: modes only when stopped; Stop only when running.
        let stopped = Settings.shared.runMode == .stop
        for item in menu.items {
            if let m = RunMode(rawValue: item.tag) {
                item.isEnabled = (m == .stop) ? !stopped : stopped
                item.state = (m == Settings.shared.runMode) ? .on : .off
            }
        }
        if let pop = runArrowBtn.window?.contentView {
            let frame = runArrowBtn.convert(runArrowBtn.bounds, to: pop)
            menu.popUp(positioning: nil, at: NSPoint(x: frame.minX, y: frame.maxY + 4), in: pop)
        }
    }

    /// Dropdown selection: start the chosen mode (or stop). Tag = TRunMode.
    @objc func runMenuClicked(_ sender: NSMenuItem) {
        guard let mode = RunMode(rawValue: sender.tag) else { return }
        if mode == .stop {
            Tst.fStopPressed = true
        } else {
            run(mode)
        }
    }

    // MARK: menu-driven send actions (Send menu, mirrors F-keys)
    @objc func sendCQMenu() { sendMsg(.cq) }
    @objc func sendNRMenu() { sendMsg(.nr) }
    @objc func sendTUMenu() { sendMsg(.tu) }
    @objc func sendMyCallMenu() { sendMsg(.myCall) }
    @objc func sendHisCallMenu() { sendMsg(.hisCall) }
    @objc func sendB4Menu() { sendMsg(.b4) }
    @objc func sendQmMenu() { sendMsg(.qm) }
    @objc func sendNilMenu() { sendMsg(.nilMsg) }

    // MARK: File menu actions
    @objc func viewScoreTable() {
        // Show the saved score strings (from .lst) in an alert.
        let url = FileManager.default.applicationSupportDirectory
            .appendingPathComponent("MorseRunner.lst")
        let text = (try? String(contentsOf: url)) ?? "Your score table is empty."
        let a = NSAlert()
        a.messageText = "Score Table"
        a.informativeText = text
        a.addButton(withTitle: "OK")
        a.beginSheetModal(for: window) { _ in }
    }
    @objc func viewScoreBoard() {
        if let url = URL(string: Settings.shared.webServer) {
            NSWorkspace.shared.open(url)
        }
    }
    @objc func toggleRecording() {
        Settings.shared.saveWav = !Settings.shared.saveWav
        refreshMenuStates()
    }

    /// Open ~/Library/Application Support/MorseRunner/ in Finder so the user
    /// can find and edit MorseRunner.ini, replace MASTER.DTA / ARRL.LIST, etc.
    @objc func revealSettingsFolder() {
        let dir = FileManager.default.applicationSupportDirectory
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
    }

    // MARK: Settings submenu actions
    /// Theme: 0 = follow system, 1 = light, 2 = dark. Applied to the app's
    /// appearance and persisted in Settings.
    @objc func setThemeMenu(_ sender: NSMenuItem) {
        Settings.shared.theme = sender.tag
        applyTheme(Settings.shared.theme)
        refreshMenuStates()
    }

    /// Apply the theme to the whole app. 0=system, 1=light, 2=dark.
    func applyTheme(_ theme: Int) {
        let appearance: NSAppearance?
        switch theme {
        case 1:  appearance = NSAppearance(named: .aqua)
        case 2:  appearance = NSAppearance(named: .darkAqua)
        default: appearance = nil   // follow system
        }
        NSApp.appearance = appearance
        // Apply to the window too so the title bar and all subviews pick up
        // the new appearance. Re-set backgroundColor to re-theme the surface.
        window.appearance = appearance
        window.backgroundColor = .windowBackgroundColor
        window.contentView?.needsDisplay = true
        histoView.needsDisplay = true
    }

    /// Map a zoom index (0/1/2) to a scale factor (1.0 / 1.5 / 2.0).
    static func zoomFactor(_ zoom: Int) -> CGFloat {
        switch zoom { case 1: return 1.5; case 2: return 2.0; default: return 1.0 }
    }

    /// Scale the entire window content proportionally. The contentView's frame
    /// is set to the scaled window size while its BOUNDS stay at the design size
    /// (730×470). When bounds ≠ frame, AppKit automatically scales the view's
    /// drawing and all subview positions by the ratio frame/bounds — enlarging
    /// every control, font, and spacing by `factor` with correct positioning.
    /// The window outer frame is resized to match so nothing is clipped.
    func applyZoom(_ zoom: Int) {
        let factor = MainController.zoomFactor(zoom)
        guard let cv = window.contentView else { return }

        let baseW: CGFloat = 730, baseH: CGFloat = 470
        let scaled = NSSize(width: ceil(baseW * factor), height: ceil(baseH * factor))

        // Relax the size lock, resize the window, then re-lock at the new size.
        window.minSize = NSSize(width: 100, height: 100)
        window.maxSize = NSSize(width: 10000, height: 10000)
        window.setContentSize(scaled)
        window.minSize = scaled
        window.maxSize = scaled

        // frame = window's scaled size; bounds = design size. The mismatch
        // makes AppKit scale all content by frame/bounds = factor.
        cv.frame = NSRect(origin: .zero, size: scaled)
        cv.bounds = NSRect(origin: .zero, size: NSSize(width: baseW, height: baseH))
        cv.needsDisplay = true
        cv.layoutSubtreeIfNeeded()
    }

    @objc func setZoomMenu(_ sender: NSMenuItem) {
        Settings.shared.zoom = sender.tag
        applyZoom(Settings.shared.zoom)
        refreshMenuStates()
    }

    @objc func setWpmMenu(_ sender: NSMenuItem) { setWpm(clamping: sender.tag, lo: 10, hi: 120) }
    @objc func setPitchMenu(_ sender: NSMenuItem) { setPitch(sender.tag) }
    @objc func setBwMenu(_ sender: NSMenuItem) { setBw(sender.tag) }
    @objc func setMonLevelMenu(_ sender: NSMenuItem) {
        // tag is the raw integer encoding (0..40); decode like setSelfMonVolume.
        volumeSlider.floatValue = Float(sender.tag) / 80.0 + 0.75
        Settings.shared.selfMonVolume = volumeSlider.floatValue
    }
    @objc func setActivityMenu(_ sender: NSMenuItem) { setActivity(sender.tag) }
    @objc func setDurationMenu(_ sender: NSMenuItem) { setDuration(sender.tag) }
    @objc func toggleQRN() { qrnCheckbox.state = (qrnCheckbox.state == .on) ? .off : .on; checkboxChanged() }
    @objc func toggleQRM() { qrmCheckbox.state = (qrmCheckbox.state == .on) ? .off : .on; checkboxChanged() }
    @objc func toggleQSB() { qsbCheckbox.state = (qsbCheckbox.state == .on) ? .off : .on; checkboxChanged() }
    @objc func toggleFlutter() { flutterCheckbox.state = (flutterCheckbox.state == .on) ? .off : .on; checkboxChanged() }
    @objc func toggleLIDS() { lidsCheckbox.state = (lidsCheckbox.state == .on) ? .off : .on; checkboxChanged() }
    @objc func toggleCallsignInfo() {
        Settings.shared.showCallsignInfo = !Settings.shared.showCallsignInfo
        infoBar.isHidden = !Settings.shared.showCallsignInfo
        refreshMenuStates()
    }

    /// Keep the checkbox-style menu items and toggles reflecting current state.
    func refreshMenuStates() {
        let flags: [(NSMenuItem?, Bool)] = [
            (togglesMenuItems.isEmpty ? nil : togglesMenuItems[0], Settings.shared.qrn),
            (togglesMenuItems.count > 1 ? togglesMenuItems[1] : nil, Settings.shared.qrm),
            (togglesMenuItems.count > 2 ? togglesMenuItems[2] : nil, Settings.shared.qsb),
            (togglesMenuItems.count > 3 ? togglesMenuItems[3] : nil, Settings.shared.flutter),
            (togglesMenuItems.count > 4 ? togglesMenuItems[4] : nil, Settings.shared.lids),
        ]
        for (item, on) in flags { item?.state = on ? .on : .off }
        recordingMenuItem?.state = Settings.shared.saveWav ? .on : .off
        callsignInfoMenuItem?.state = Settings.shared.showCallsignInfo ? .on : .off
        // Theme: tick the active theme item.
        for item in themeMenuItems {
            item.state = (item.tag == Settings.shared.theme) ? .on : .off
        }
        // Zoom: tick the active zoom item.
        for item in zoomMenuItems {
            item.state = (item.tag == Settings.shared.zoom) ? .on : .off
        }
    }

    // MARK: - menu bar

    private func buildMenuBar() {
        let mainMenu = NSMenu()

        // App menu (Apple-provided style)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Morse Runner", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu — score table, hi-score web page, audio recording, settings folder, exit.
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "View Score Table", action: #selector(viewScoreTable), keyEquivalent: "")
        fileMenu.addItem(withTitle: "View Hi-Score Web Page...", action: #selector(viewScoreBoard), keyEquivalent: "")
        fileMenu.addItem(.separator())
        let recItem = fileMenu.addItem(withTitle: "Audio Recording Enabled", action: #selector(toggleRecording), keyEquivalent: "")
        recItem.target = self
        fileMenu.addItem(.separator())
        let revealItem = fileMenu.addItem(withTitle: "Reveal Settings Folder", action: #selector(revealSettingsFolder), keyEquivalent: "")
        revealItem.target = self
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // Run menu
        let runMenuItem = NSMenuItem()
        let runMenu = NSMenu(title: "Run")
        runMenu.addItem(withTitle: "Pile-Up", action: #selector(runPileUp), keyEquivalent: "")
        runMenu.addItem(withTitle: "Single Calls", action: #selector(runSingle), keyEquivalent: "")
        runMenu.addItem(withTitle: "WPX Competition", action: #selector(runWpx), keyEquivalent: "")
        runMenu.addItem(withTitle: "HST Competition", action: #selector(runHst), keyEquivalent: "")
        runMenu.addItem(.separator())
        runMenu.addItem(withTitle: "Stop", action: #selector(runStop), keyEquivalent: ".")
        runMenuItem.submenu = runMenu
        mainMenu.addItem(runMenuItem)

        // Send menu — mirrors the F-key buttons (accessibility / blind hams).
        let sendItem = NSMenuItem()
        let sendMenu = NSMenu(title: "Send")
        sendMenu.addItem(withTitle: "CQ", action: #selector(sendCQMenu), keyEquivalent: "")
        sendMenu.addItem(withTitle: "Number", action: #selector(sendNRMenu), keyEquivalent: "")
        sendMenu.addItem(withTitle: "TU", action: #selector(sendTUMenu), keyEquivalent: "")
        sendMenu.addItem(withTitle: "My Call", action: #selector(sendMyCallMenu), keyEquivalent: "")
        sendMenu.addItem(withTitle: "His Call", action: #selector(sendHisCallMenu), keyEquivalent: "")
        sendMenu.addItem(withTitle: "QSO B4", action: #selector(sendB4Menu), keyEquivalent: "")
        sendMenu.addItem(.separator())
        sendMenu.addItem(withTitle: "?", action: #selector(sendQmMenu), keyEquivalent: "")
        sendMenu.addItem(withTitle: "NIL", action: #selector(sendNilMenu), keyEquivalent: "")
        sendItem.submenu = sendMenu
        mainMenu.addItem(sendItem)

        // Settings menu — full set of submenus like the original.
        let settingsItem = NSMenuItem()
        let settingsMenu = NSMenu(title: "Settings")
        settingsMenu.addItem(withTitle: "Callsign…", action: #selector(editCallsign), keyEquivalent: "")
        // CW Speed submenu (10..60 WPM in 5 WPM steps)
        let speedItem = settingsMenu.addItem(withTitle: "CW Speed", action: nil, keyEquivalent: "")
        let speedMenu = NSMenu(title: "CW Speed")
        for w in stride(from: 10, through: 60, by: 5) {
            speedMenu.addItem(withTitle: "\(w) WPM", action: #selector(setWpmMenu(_:)),
                              keyEquivalent: "").tag = w
        }
        speedItem.submenu = speedMenu
        // CW Pitch submenu
        let pitchItem = settingsMenu.addItem(withTitle: "CW Pitch", action: nil, keyEquivalent: "")
        let pitchMenu = NSMenu(title: "CW Pitch")
        for i in 0..<14 {
            pitchMenu.addItem(withTitle: "\(300 + i*50) Hz", action: #selector(setPitchMenu(_:)),
                              keyEquivalent: "").tag = i
        }
        pitchItem.submenu = pitchMenu
        // CW Bandwidth submenu
        let bwItem = settingsMenu.addItem(withTitle: "CW Bandwidth", action: nil, keyEquivalent: "")
        let bwMenu = NSMenu(title: "CW Bandwidth")
        for i in 0..<9 {
            bwMenu.addItem(withTitle: "\(100 + i*50) Hz", action: #selector(setBwMenu(_:)),
                          keyEquivalent: "").tag = i
        }
        bwItem.submenu = bwMenu
        // Mon. Level submenu
        let monItem = settingsMenu.addItem(withTitle: "Mon. Level", action: nil, keyEquivalent: "")
        let monMenu = NSMenu(title: "Mon. Level")
        for (label, val) in [("-60 dB", 0), ("-40 dB", 10), ("-20 dB", 20), ("0 dB", 30), ("+20 dB", 40)] {
            monMenu.addItem(withTitle: label, action: #selector(setMonLevelMenu(_:)),
                           keyEquivalent: "").tag = val
        }
        monItem.submenu = monMenu
        settingsMenu.addItem(.separator())
        // Band-condition toggles
        let qrnItem = settingsMenu.addItem(withTitle: "QRN", action: #selector(toggleQRN), keyEquivalent: "")
        let qrmItem = settingsMenu.addItem(withTitle: "QRM", action: #selector(toggleQRM), keyEquivalent: "")
        let qsbItem = settingsMenu.addItem(withTitle: "QSB", action: #selector(toggleQSB), keyEquivalent: "")
        let fltItem = settingsMenu.addItem(withTitle: "Flutter", action: #selector(toggleFlutter), keyEquivalent: "")
        let lidsItem = settingsMenu.addItem(withTitle: "LIDS", action: #selector(toggleLIDS), keyEquivalent: "")
        for it in [qrnItem, qrmItem, qsbItem, fltItem, lidsItem] { it.target = self }
        // Activity submenu
        let actItem = settingsMenu.addItem(withTitle: "Activity", action: nil, keyEquivalent: "")
        let actMenu = NSMenu(title: "Activity")
        for a in 1...9 {
            actMenu.addItem(withTitle: "\(a)", action: #selector(setActivityMenu(_:)),
                           keyEquivalent: "").tag = a
        }
        actItem.submenu = actMenu
        settingsMenu.addItem(.separator())
        // Duration submenu
        let durItem = settingsMenu.addItem(withTitle: "Duration", action: nil, keyEquivalent: "")
        let durMenu = NSMenu(title: "Duration")
        for d in [5, 10, 15, 30, 60, 90, 120] {
            durMenu.addItem(withTitle: "\(d) min", action: #selector(setDurationMenu(_:)),
                           keyEquivalent: "").tag = d
        }
        durItem.submenu = durMenu
        settingsMenu.addItem(withTitle: "HST Operator…", action: #selector(editOperator), keyEquivalent: "")
        settingsMenu.addItem(.separator())
        let infoItem = settingsMenu.addItem(withTitle: "Show Callsign Info", action: #selector(toggleCallsignInfo), keyEquivalent: "")
        infoItem.target = self
        // Theme submenu: System / Dark / Light appearance.
        let themeItem = settingsMenu.addItem(withTitle: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "Theme")
        let themes: [(String, Int)] = [("Follow System", 0), ("Light", 1), ("Dark", 2)]
        themeMenuItems = []
        for (label, tag) in themes {
            let item = themeMenu.addItem(withTitle: label, action: #selector(setThemeMenu(_:)),
                                         keyEquivalent: "")
            item.tag = tag
            item.target = self
            themeMenuItems.append(item)
        }
        themeItem.submenu = themeMenu
        // Zoom submenu: 100% / 150% / 200% — scales the entire window.
        let zoomItem = settingsMenu.addItem(withTitle: "Zoom", action: nil, keyEquivalent: "")
        let zoomMenu = NSMenu(title: "Zoom")
        let zooms: [(String, Int)] = [("100%", 0), ("150%", 1), ("200%", 2)]
        zoomMenuItems = []
        for (label, tag) in zooms {
            let item = zoomMenu.addItem(withTitle: label, action: #selector(setZoomMenu(_:)),
                                        keyEquivalent: "")
            item.tag = tag
            item.target = self
            zoomMenuItems.append(item)
        }
        zoomItem.submenu = zoomMenu
        settingsItem.submenu = settingsMenu
        mainMenu.addItem(settingsItem)

        // Help menu
        let helpItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Web Page…", action: #selector(openWebsite), keyEquivalent: "")
        helpMenu.addItem(.separator())
        helpMenu.addItem(withTitle: "About…", action: #selector(about), keyEquivalent: "")
        helpItem.submenu = helpMenu
        mainMenu.addItem(helpItem)

        NSApp.mainMenu = mainMenu

        // keep the checkbox-style menu items reflecting current state
        self.togglesMenuItems = [qrnItem, qrmItem, qsbItem, fltItem, lidsItem]
        self.recordingMenuItem = recItem
        self.callsignInfoMenuItem = infoItem
        refreshMenuStates()
    }

    @objc func about() {
        let a = NSAlert()
        a.messageText = "CW Contest Simulator"
        a.informativeText = """
            Morse Runner \(sVersion)

            Copyright ©2004-2016 Alex Shovkoplyas, VE3NEA
            ve3nea@dxatlas.com

            Modified by BG4FQD.
            Ported to macOS by BH4BQI.
            """
        a.addButton(withTitle: "OK")
        a.beginSheetModal(for: window) { _ in }
    }

    @objc func runPileUp() { run(.pileUp) }
    @objc func runSingle() { run(.single) }
    @objc func runWpx() { run(.wpx) }
    @objc func runHst() { run(.hst) }
    @objc func runStop() { Tst.fStopPressed = true }

    @objc func editCallsign() {
        let a = NSAlert()
        a.messageText = "Callsign"
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        let tf = NSTextField(string: myCallField.stringValue)
        tf.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        a.accessoryView = tf
        a.beginSheetModal(for: window) { resp in
            if resp == .alertFirstButtonReturn {
                self.setMyCall(tf.stringValue.trimmingCharacters(in: .whitespaces))
            }
        }
    }

    @objc func editOperator() {
        let a = NSAlert()
        a.messageText = "HST Operator"
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        let tf = NSTextField(string: Settings.shared.hamName)
        tf.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        a.accessoryView = tf
        a.beginSheetModal(for: window) { resp in
            if resp == .alertFirstButtonReturn {
                Settings.shared.hamName = tf.stringValue
                self.window.title = "Morse Runner \(sVersion):  \(tf.stringValue)"
            }
        }
    }

    @objc func openWebsite() {
        if let url = URL(string: "http://www.dxatlas.com/MorseRunner") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - keyboard handling

extension MainController: NSTextFieldDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        guard let control = obj.object as? NSControl else { return }
        if control === callField {
            if callField.stringValue.isEmpty {
                QsoLog.shared.nrSent = false
            }
            if !Tst.me.updateCallInMessage(callField.stringValue) {
                QsoLog.shared.callSent = false
            }
        }
    }

    /// Replicates Edit1Enter / Edit2Enter: when focus enters a field, select the
    /// relevant sub-range so the next keystroke overwrites it.
    ///   - Call field (Edit1): if the text contains '?', select that character
    ///     (the user is correcting a mis-copy).
    ///   - RST field (Edit2): if it has 3 digits, select the middle digit.
    public func controlTextDidBeginEditing(_ obj: Notification) {
        guard let control = obj.object as? NSControl else { return }
        if control === callField, let editor = callField.currentEditor() {
            // Select the '?' if present (Edit1Enter).
            if let qIdx = callField.stringValue.firstIndex(of: "?") {
                let nsIdx = callField.stringValue.distance(from: callField.stringValue.startIndex, to: qIdx)
                editor.selectedRange = NSRange(location: nsIdx, length: 1)
            }
        } else if control === rstField, let editor = rstField.currentEditor() {
            // Select the middle digit of a 3-digit RST (Edit2Enter).
            if rstField.stringValue.count == 3 {
                editor.selectedRange = NSRange(location: 1, length: 1)
            }
        }
    }

    /// NSTextFieldDelegate command dispatch. The field editor calls this for
    /// special key actions (Return → insertNewline:, Tab → insertTab:, Esc →
    /// cancelOperation:, arrows → moveDown:/moveUp:, etc.). We use it as the
    /// reliable interception point for Enter/Return, Space, and the contest
    /// characters while a field has focus — `handleKeyEvent` then runs the
    /// full ESM/F-key logic.
    ///
    /// This is the macOS equivalent of Delphi's `KeyPreview = True` for the
    /// keys the field editor would otherwise consume.
    public func control(_ control: NSControl,
                        textView: NSTextView,
                        doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            // Return/Enter → ESM.
            processEnter(modifiers: NSEvent.modifierFlags)
            return true
        case #selector(NSResponder.insertTab(_:)):
            // Tab → next field, cycling Call → RST → NR → Call. (The original
            // relied on VCL TabOrder; here we make it an explicit cycle so the
            // cursor stays in the contest fields and you can Tab back to the
            // Call field to correct a mis-copied callsign.)
            moveFocus(forward: true)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            // Shift-Tab → previous field, cycling Call → NR → RST → Call.
            moveFocus(forward: false)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            // Esc → abort send.
            _ = handleKeyEvent(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: 0x35)!)
            return true
        default:
            return false
        }
    }

    /// Move focus between the three contest input fields in a cycle.
    /// Forward: Call → RST → NR → Call. Backward: Call → NR → RST → Call.
    /// When entering RST with empty text, auto-fill "599" (ProcessSpace rule).
    func moveFocus(forward: Bool) {
        let cycle = [callField, rstField, nrField]
        guard let current = window.firstResponder as? NSTextView,
              let host = current.delegate as? NSTextField,
              let idx = cycle.firstIndex(where: { $0 === host }) else {
            // Not in a contest field — just focus Call.
            window.makeFirstResponder(callField)
            return
        }
        let n = cycle.count
        let next = forward ? (idx + 1) % n : (idx + n - 1) % n
        let target = cycle[next]
        // Auto-fill RST to 599 when entering it empty (matches Space behaviour).
        if target === rstField, rstField.stringValue.isEmpty {
            rstField.stringValue = "599"
        }
        window.makeFirstResponder(target)
    }
}

// MARK: - global keyboard
//
// Contest command keys (Enter, Space, ;, ., +, [, ,, Esc, and the F-keys) are
// intercepted by two cooperating mechanisms:
//   1. ContestFieldEditor (the field editor for the Call/RST/NR fields) forwards
//      them to MainController.handleKeyEvent before inserting text — this is
//      what makes "Enter on empty call → CQ" work while a field has focus.
//   2. MainWindowClass.performKeyEquivalent / keyDown catch the function keys,
//      arrows, PgUp/Dn, and Escape whether or not a field has focus.
//
// The old MainKeyView/nextResponder approach was removed: a focused NSTextField's
// field editor consumes Return/Space/printable chars and never passes them up
// the responder chain, so the window's keyDown never saw them.
