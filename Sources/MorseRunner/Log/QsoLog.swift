//
//  QsoLog.swift
//  Port of Log.pas — QSO log + scoring.
//
//  Records each completed QSO, checks it against the DX station's "true" data
//  (call/RST/NR), and computes WPX (points × prefixes) and HST (CW-character)
//  scores plus the running QSO rate.
//

import Foundation
import AppKit

public struct Qso {
    public var t: Float = 0                  // seconds / 86400 (day fraction)
    public var call: String = ""
    public var trueCall: String = ""
    public var rawCallsign: String = ""
    public var rst: Int = 599
    public var trueRst: Int = 599
    public var nr: Int = 0
    public var trueNr: Int = 0
    public var pfx: String = ""
    public var dupe: Bool = false
    public var err: String = "   "
}

public protocol ScoreTableDelegate: AnyObject {
    func scoreTableSetTitle(_ c1: String, _ c2: String, _ c3: String, _ c4: String, _ c5: String, _ c6: String)
    func scoreTableInsert(_ c1: String, _ c2: String, _ c3: String, _ c4: String, _ c5: String, _ c6: String)
    /// Clear all rows from the QSO log table (used when starting a fresh run).
    func scoreTableClear()
    func scoreTableUpdateLastError(_ err: String)
    /// Update the Chk cell of a specific row (by index) — used when a DX
    /// station delivers its true data into an earlier-than-last QSO.
    func scoreTableUpdateRowError(_ row: Int, _ err: String)
    func scoreViewSetNeedsDisplay()
    func setRawScore(_ idx: Int, value: String)   // idx 0..2 = QSOs, mult, score
    func setVerifiedScore(_ idx: Int, value: String)
    func setRateText(_ text: String)
    func setRunClockText(_ text: String)
    func setPileUpCount(_ count: Int, isPileUp: Bool)
    /// Update the callsign-info bar with the DXCC entity for a callsign.
    func setInfoBar(_ text: String)
}

public final class QsoLog {
    public static let shared = QsoLog()

    // Backing storage is private; all access is serialized through `lock` so the
    // realtime audio thread and the main thread can't race on the QSO list.
    private var _qsoList: [Qso] = []
    private var _pfxList: Set<String> = []
    private var _callSent: Bool = false
    private var _nrSent: Bool = false
    private var lock = os_unfair_lock_s()

    public weak var histo: Histo?
    public weak var delegate: ScoreTableDelegate?

    private init() {}

    // MARK: - thread-safe accessors

    public var qsoList: [Qso] {
        get { withLock { _qsoList } }
    }
    public var pfxList: Set<String> {
        get { withLock { _pfxList } }
    }
    public var callSent: Bool {
        get { withLock { _callSent } }
        set { withLock { _callSent = newValue } }
    }
    public var nrSent: Bool {
        get { withLock { _nrSent } }
        set { withLock { _nrSent = newValue } }
    }

    public var last: Qso? {
        get { withLock { _qsoList.last } }
    }

    /// Set the true call/RST/NR for the QSO matching `call`. Searches backwards
    /// from the most recent QSO and fills the first match whose `trueCall` is
    /// still empty — so each DX station's data lands in the correct log entry
    /// even when several QSOs were saved before the DX finished (common in
    /// pile-up). Returns the row index that was filled (for checkErr), or nil.
    /// Thread-safe; called from the audio thread.
    @discardableResult
    public func updateLastTrueCall(_ call: String, rst: Int, nr: Int) -> Int? {
        let idx = withLock { () -> Int? in
            // Prefer an exact match for this call that hasn't been filled yet.
            var i = _qsoList.count - 1
            while i >= 0 {
                if _qsoList[i].trueCall.isEmpty && _qsoList[i].call == call {
                    return i
                }
                i -= 1
            }
            // Fallback: the original behaviour — fill the very last entry.
            // (Reached when the operator copied the call incorrectly, so the
            //  entered call never matches the DX's true call exactly.)
            if !_qsoList.isEmpty { return _qsoList.count - 1 }
            return nil
        }
        guard let i = idx else { return nil }
        withLock {
            _qsoList[i].trueCall = call
            _qsoList[i].trueRst = rst
            _qsoList[i].trueNr = nr
        }
        return i
    }

    @inline(__always)
    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return body()
    }

    /// True if any QSO in the log matches `call` and hasn't yet received its
    /// true data. Used by the Contest loop to decide whether a newly-completed
    /// DX station still has data to deliver. Thread-safe.
    public func hasUnfilledQso(for call: String) -> Bool {
        withLock {
            _qsoList.contains { $0.trueCall.isEmpty && $0.call == call }
        }
    }

    // MARK: clear / setup

    public func clear() {
        withLock {
            _qsoList.removeAll()
            _pfxList.removeAll()
        }
        // Clear the visible QSO log table rows so a fresh Run starts empty.
        delegate?.scoreTableClear()
        if Settings.shared.runMode == .hst {
            delegate?.scoreTableSetTitle("UTC", "Call", "Recv", "Sent", "Score", "Chk")
        } else {
            delegate?.scoreTableSetTitle("UTC", "Call", "Recv", "Sent", "Pref", "Chk")
        }
        let emptyRaw = Settings.shared.runMode == .hst ? "" : formatScore(0)
        for i in 0..<2 {
            delegate?.setRawScore(i, value: emptyRaw)
            delegate?.setVerifiedScore(i, value: emptyRaw)
        }
        delegate?.setRawScore(2, value: formatScore(0))
        delegate?.setVerifiedScore(2, value: formatScore(0))
        delegate?.scoreViewSetNeedsDisplay()
    }

    // MARK: save QSO

    public func saveQso(callField: String, rstField: String, nrField: String) {
        guard callField.count >= 3, rstField.count == 3, !nrField.isEmpty else {
            NSSound.beep()
            return
        }

        var qso = Qso()
        qso.t = blocksToSeconds(Float(Tst.blockNumber)) / 86400.0
        qso.call = callField.replacingOccurrences(of: "?", with: "")
        qso.rst = Int(rstField) ?? 599
        qso.nr = Int(nrField) ?? 0
        qso.rawCallsign = extractCallsign(qso.call)
        qso.pfx = extractPrefix(qso.rawCallsign)
        if Settings.shared.runMode == .hst {
            qso.pfx = String(callToScore(qso.call))
        }

        // duplicate? (hold the lock for the append so it's atomic with the check)
        withLock {
            _pfxList.insert(qso.pfx)
            qso.dupe = false
            for prev in _qsoList where prev.call == qso.call && prev.err == "   " {
                qso.dupe = true
            }
            _qsoList.append(qso)
        }

        // pull the DX station's true data
        for s in Tst.stations.items {
            if let dx = s as? DxStation,
               dx.oper.state == .done,
               dx.myCall == qso.call {
                dx.dataToLastQso()
                break
            }
        }
        checkErr()
        lastQsoToScreen()
        if Settings.shared.runMode == .hst { updateStatsHst() } else { updateStats() }

        // wipe + increment NR
        MainController.shared?.wipeBoxes()
        Tst.me.nr += 1
    }

    public func lastQsoToScreen() {
        guard let q = last else { return }
        let t = formatClock(q.t)
        let recv = String(format: "%03d %04d", q.rst, q.nr)
        let sent = String(format: "%03d %04d", Tst.me.rst, Tst.me.nr)
        delegate?.scoreTableInsert(t, q.call, recv, sent, q.pfx, q.err)
        // Callsign info bar (UpdateSbar): show the DXCC entity for this call.
        if Settings.shared.showCallsignInfo {
            let info = ArrlList.shared.search(q.call)
            delegate?.setInfoBar(info.isEmpty ? "  \(q.call)  Unknown" : "  \(info)")
        }
    }

    /// Recompute the err flag for the QSO at `idx` and push it to the table.
    /// Used after a DX station delivers its true data (possibly into an earlier
    /// row, not the last one). When `idx` is nil, defaults to the last QSO.
    public func checkErr(at idx: Int? = nil) {
        let (rowIdx, err) = withLock { () -> (Int, String) in
            guard !_qsoList.isEmpty else { return (0, "   ") }
            let i = idx ?? (_qsoList.count - 1)
            let q = _qsoList[i]
            let e: String
            if q.trueCall.isEmpty {
                e = "NIL"
            } else if q.dupe {
                e = "DUP"
            } else if q.trueRst != q.rst {
                e = "RST"
            } else if q.trueNr != q.nr {
                e = "NR "
            } else {
                e = "   "
            }
            _qsoList[i].err = e
            return (i, e)
        }
        delegate?.scoreTableUpdateRowError(rowIdx, err)
    }

    /// Back-compat: recheck the last QSO and update its table row.
    public func scoreTableUpdateCheck() {
        checkErr(at: nil)
    }

    // MARK: scoring

    public func callToScore(_ s: String) -> Int {
        let code = Keyer.encode(s)
        var result = -1
        for c in code {
            switch c {
            case ".": result += 2
            case "-": result += 4
            case " ": result += 2
            default: break
            }
        }
        return result
    }

    public func updateStats() {
        // raw
        var pts = qsoList.count
        var pfxRaw = Set<String>()
        for q in qsoList { pfxRaw.insert(q.pfx) }
        var mul = pfxRaw.count
        delegate?.setRawScore(0, value: formatScore(pts))
        delegate?.setRawScore(1, value: formatScore(mul))
        delegate?.setRawScore(2, value: formatScore(pts * mul))

        // verified
        pts = 0
        var pfxVer = Set<String>()
        for q in qsoList where q.err == "   " {
            pts += 1
            pfxVer.insert(q.pfx)
        }
        mul = pfxVer.count
        delegate?.setVerifiedScore(0, value: formatScore(pts))
        delegate?.setVerifiedScore(1, value: formatScore(mul))
        delegate?.setVerifiedScore(2, value: formatScore(pts * mul))
        delegate?.scoreViewSetNeedsDisplay()
    }

    public func updateStatsHst() {
        var rawScore = 0
        var score = 0
        for q in qsoList {
            let cs = callToScore(q.call)
            rawScore += cs
            if q.err == "   " { score += cs }
        }
        delegate?.setRawScore(0, value: "")
        delegate?.setRawScore(1, value: "")
        delegate?.setRawScore(2, value: formatScore(rawScore))
        delegate?.setVerifiedScore(0, value: "")
        delegate?.setVerifiedScore(1, value: "")
        delegate?.setVerifiedScore(2, value: formatScore(score))
        delegate?.scoreViewSetNeedsDisplay()
    }

    public func showRate() {
        let t = blocksToSeconds(Float(Tst.blockNumber)) / 86400.0
        if t == 0 { return }
        let d = min(Float(5) / 1440, t)
        var cnt = 0
        for q in qsoList.reversed() {
            if q.t > (t - d) { cnt += 1 } else { break }
        }
        let rate = Int(Float(cnt) / d / 24)
        delegate?.setRateText("\(rate)  qso/hr.")
    }

    // MARK: helpers

    public func formatScore(_ value: Int) -> String {
        return String(format: "%6d", value)
    }

    private func formatClock(_ dayFraction: Float) -> String {
        let total = Int(dayFraction * 86400)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
