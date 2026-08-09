//
//  Station.swift
//  Port of Station.pas — base TStation.
//
//  A station (you, a DX caller, QRM/QRN interferer) holds an amplitude
//  envelope being played out, a CW pitch/BFO phase, and a state machine driven
//  by events (timeout / message sent / me started / me finished).
//

import Foundation

// MARK: - Messages (Station.pas: TStationMessage / TStationMessages)

public enum StationMessage: Int, CaseIterable {
    case none = 0, cq, nr, tu, myCall, hisCall
    case b4, qm, nilMsg, garbage
    case r_nr, r_nr2, deMyCall1, deMyCall2, deMyCallNr1, deMyCallNr2
    case nrQm, longCQ, myCallNr2, qrl, qrl2, qsy, agn
}

/// A set of station messages (mirrors `set of TStationMessage`).
public struct StationMessages: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let none     = StationMessages([])
    public static let cq       = StationMessages(rawValue: 1 << StationMessage.cq.rawValue)
    public static let nr       = StationMessages(rawValue: 1 << StationMessage.nr.rawValue)
    public static let tu       = StationMessages(rawValue: 1 << StationMessage.tu.rawValue)
    public static let myCall   = StationMessages(rawValue: 1 << StationMessage.myCall.rawValue)
    public static let hisCall  = StationMessages(rawValue: 1 << StationMessage.hisCall.rawValue)
    public static let b4       = StationMessages(rawValue: 1 << StationMessage.b4.rawValue)
    public static let qm       = StationMessages(rawValue: 1 << StationMessage.qm.rawValue)
    public static let nilMsg   = StationMessages(rawValue: 1 << StationMessage.nilMsg.rawValue)
    public static let garbage  = StationMessages(rawValue: 1 << StationMessage.garbage.rawValue)
    public static let r_nr     = StationMessages(rawValue: 1 << StationMessage.r_nr.rawValue)
    public static let r_nr2    = StationMessages(rawValue: 1 << StationMessage.r_nr2.rawValue)
    public static let deMyCall1 = StationMessages(rawValue: 1 << StationMessage.deMyCall1.rawValue)
    public static let deMyCall2 = StationMessages(rawValue: 1 << StationMessage.deMyCall2.rawValue)
    public static let deMyCallNr1 = StationMessages(rawValue: 1 << StationMessage.deMyCallNr1.rawValue)
    public static let deMyCallNr2 = StationMessages(rawValue: 1 << StationMessage.deMyCallNr2.rawValue)
    public static let nrQm     = StationMessages(rawValue: 1 << StationMessage.nrQm.rawValue)
    public static let longCQ   = StationMessages(rawValue: 1 << StationMessage.longCQ.rawValue)
    public static let myCallNr2 = StationMessages(rawValue: 1 << StationMessage.myCallNr2.rawValue)
    public static let qrl      = StationMessages(rawValue: 1 << StationMessage.qrl.rawValue)
    public static let qrl2     = StationMessages(rawValue: 1 << StationMessage.qrl2.rawValue)
    public static let qsy      = StationMessages(rawValue: 1 << StationMessage.qsy.rawValue)
    public static let agn      = StationMessages(rawValue: 1 << StationMessage.agn.rawValue)
}

// MARK: - State & events

public enum StationState: Int {
    case listening = 0, copying, preparingToSend, sending
}

public enum StationEvent: Int {
    case timeout, msgSent, meStarted, meFinished
}

// MARK: - TStation base class

public class Station {
    // BFO phase management (each station has its own carrier phase offset).
    public private(set) var bfo: Float = 0
    private var dPhi: Float = 0
    private var fPitch: Int = 0

    var sendPos: Int = 0
    var timeout: Int = NEVER
    var nrWithError: Bool = false

    public var amplitude: Float = 0
    public var wpm: Int = 30
    public var envelope: [Float] = []
    public var state: StationState = .listening

    public var nr: Int = 1
    public var rst: Int = 599
    public var myCall: String = ""
    public var hisCall: String = ""

    public var msg: StationMessages = .none
    public var msgText: String = ""

    public init() {}

    public var pitch: Int {
        get { fPitch }
        set {
            fPitch = newValue
            dPhi = TWO_PI * Float(fPitch) / Float(DEFAULTRATE)
        }
    }

    /// Read the current BFO and advance it by dPhi for next time.
    public func currentBfo() -> Float {
        let result = bfo
        bfo += dPhi
        if bfo > TWO_PI { bfo -= TWO_PI }
        return result
    }

    /// Fetch one audio block (and advance the TX buffer). Returns a short block
    /// (fewer than bufSize samples) when near the end of the envelope — the
    // caller uses blk.count, NOT bufSize, to avoid mixing in stale/zero data
    // that causes clicks.
    public func getBlock() -> [Float] {
        let bufSize = Settings.shared.bufSize
        let end = min(sendPos + bufSize, envelope.count)
        let block = Array(envelope[sendPos..<end])
        sendPos += bufSize
        if sendPos >= envelope.count {
            envelope.removeAll(keepingCapacity: true)
        }
        return block
    }

    public func sendMsg(_ aMsg: StationMessage) {
        if envelope.isEmpty {
            msg = .none
        }
        if aMsg == .none {
            state = .listening
            return
        }
        msg.insert(StationMessages(rawValue: 1 << aMsg.rawValue))

        switch aMsg {
        case .cq:       sendText("CQ <my> TEST")
        case .nr:       sendText("<#>")
        case .tu:       sendText("TU")
        case .myCall:   sendText("<my>")
        case .hisCall:  sendText("<his>")
        case .b4:       sendText("QSO B4")
        case .qm:       sendText("?")
        case .nilMsg:   sendText("NIL")
        case .r_nr:     sendText("R <#>")
        case .r_nr2:    sendText("R <#> <#>")
        case .deMyCall1:   sendText("DE <my>")
        case .deMyCall2:   sendText("DE <my> <my>")
        case .deMyCallNr1: sendText("DE <my> <#>")
        case .deMyCallNr2: sendText("DE <my> <my> <#>")
        case .myCallNr2:   sendText("<my> <my> <#>")
        case .nrQm:     sendText("NR?")
        case .longCQ:   sendText("CQ CQ TEST <my> <my> TEST")
        case .qrl:      sendText("QRL?")
        case .qrl2:     sendText("QRL?   QRL?")
        case .qsy:      sendText("<his>  QSY QSY")
        case .agn:      sendText("AGN")
        default: break
        }
    }

    /// Default text-sending behaviour (overridden by MyStation).
    public func sendText(_ aMsg: String) {
        var s = aMsg
        // expand exchange number(s): first occurrence (with possible error),
        // then the rest.
        if s.contains("<#>") {
            s = replaceFirst(s, "<#>", nrAsText())
            s = s.replacingOccurrences(of: "<#>", with: nrAsText())
        }
        s = s.replacingOccurrences(of: "<my>", with: myCall)
        s = s.replacingOccurrences(of: "<his>", with: hisCall)

        if !msgText.isEmpty {
            msgText = msgText + " " + s
        } else {
            msgText = s
        }
        sendMorse(Keyer.encode(msgText))
    }

    public func sendMorse(_ aMorse: String) {
        if envelope.isEmpty {
            sendPos = 0
            bfo = 0
        }
        Keyer.wpm = wpm
        Keyer.morseMsg = aMorse
        envelope = Keyer.envelope
        for i in 0..<envelope.count {
            envelope[i] *= amplitude
        }
        state = .sending
        timeout = NEVER
    }

    /// Advance the station one audio block; fire events as state changes.
    public func tick() {
        // just finished sending
        if state == .sending && envelope.isEmpty {
            msgText = ""
            state = .listening
            processEvent(.msgSent)
        } else if state != .sending {
            // check timeout
            if timeout > -1 { timeout -= 1 }
            if timeout == 0 {
                processEvent(.timeout)
            }
        }
    }

    public func processEvent(_ event: StationEvent) {
        // subclasses override
    }

    // MARK: exchange number formatting (NrAsText)

    func nrAsText() -> String {
        // Format as "<RST><NR 3-digit>" → e.g. "5990001" for RST=599, NR=1.
        var chars = Array(String(format: "%d%03d", rst, nr))
        let digitSet = Set("234567")

        if nrWithError {
            // Pick an index whose digit is in '2'..'7', preferring the last char.
            let valid: [Bool] = chars.map { digitSet.contains($0) }
            var idx = chars.count - 1
            if !valid[idx] { idx -= 1 }
            if idx >= 0 && valid[idx] {
                let d = chars[idx]
                let newScalar = UnicodeScalar(Int(d.asciiValue!) + (rnd() < 0.5 ? -1 : 1))!
                chars[idx] = Character(newScalar)
                chars += Array(String(format: "EEEEE %03d", nr))
            }
            nrWithError = false
        }

        var result = String(chars)
        result = result.replacingOccurrences(of: "599", with: "5NN")

        if Settings.shared.runMode != .hst {
            result = result.replacingOccurrences(of: "000", with: "TTT")
            result = result.replacingOccurrences(of: "00", with: "TT")
            if rnd() < 0.4 {
                result = result.replacingOccurrences(of: "0", with: "O")
            } else if rnd() < 0.97 {
                result = result.replacingOccurrences(of: "0", with: "T")
            }
            if rnd() < 0.97 {
                result = result.replacingOccurrences(of: "9", with: "N")
            }
        }
        return result
    }

    /// Replace the first occurrence of `target` with `replacement` (helper for
    /// the `<#>` expansion, mirroring StringReplace with max=1).
    private func replaceFirst(_ s: String, _ target: String, _ replacement: String) -> String {
        guard let r = s.range(of: target) else { return s }
        return s.replacingCharacters(in: r, with: replacement)
    }
}
