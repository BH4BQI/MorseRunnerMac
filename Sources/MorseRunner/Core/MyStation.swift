//
//  MyStation.swift
//  Port of MyStn.pas — TMyStation (the operator's own station).
//
//  Splits outgoing messages into "pieces", with a special placeholder '@'
//  marking where the DX callsign goes. This lets the call be sent (and
//  corrected mid-send) as the user types it. Also supports the
//  CallsFromKeyer mode where the callsign is entered manually rather than
//  played by the computer.
//

import Foundation

public final class MyStation: Station {
    private var pieces: [String] = []   // '@' marks a callsign piece

    /// Number of pending message pieces (test/diagnostic helper).
    public var piecesCount: Int { pieces.count }
    /// Whether the currently-sending piece is a callsign slot (test helper).
    public var isSendingCallsign: Bool { !pieces.isEmpty && pieces[0] == "@" }

    public override init() {
        super.init()
        initStation()
    }

    public func initStation() {
        myCall = Settings.shared.call
        nr = 1
        rst = 599
        pitch = Settings.shared.pitch
        wpm = Settings.shared.wpm
        amplitude = 300000
    }

    public override func processEvent(_ event: StationEvent) {
        if event == .msgSent {
            Tst.onMeFinishedSending()
        }
    }

    public func abortSend() {
        envelope.removeAll(keepingCapacity: true)
        msg = .garbage
        msgText = ""
        pieces.removeAll(keepingCapacity: true)
        state = .listening
        processEvent(.msgSent)
    }

    public override func sendText(_ aMsg: String) {
        addToPieces(aMsg)
        if state != .sending {
            sendNextPiece()
            Tst.onMeStartedSending()
        }
    }

    /// Split a message on `<his>` into pieces, marking each callsign slot with '@'.
    private func addToPieces(_ aMsg: String) {
        var rest = aMsg
        while let r = rest.range(of: "<his>") {
            let before = String(rest[rest.startIndex..<r.lowerBound])
            if !before.isEmpty { pieces.append(before) }
            pieces.append("@")   // his-callsign indicator
            rest = String(rest[r.upperBound..<rest.endIndex])
        }
        if !rest.isEmpty { pieces.append(rest) }
    }

    private func sendNextPiece() {
        msgText = ""
        guard !pieces.isEmpty else { return }
        if pieces[0] != "@" {
            super.sendText(pieces[0])
        } else if Settings.shared.callsFromKeyer,
                  Settings.shared.runMode != .hst,
                  Settings.shared.runMode != .wpx {
            super.sendText(" ")
        } else {
            super.sendText(hisCall)
        }
    }

    public override func getBlock() -> [Float] {
        let result = super.getBlock()
        if envelope.isEmpty {
            // current piece finished; advance to the next
            if !pieces.isEmpty { pieces.removeFirst() }
            if !pieces.isEmpty { sendNextPiece() }
            // move the UI cursor to the exchange field when appropriate
            MainController.shared?.advance()
        }
        return result
    }

    /// Try to update the callsign currently being sent (or scheduled).
    /// Returns true if the update could be applied without restarting.
    ///
    /// Called from `controlTextDidChange` on the main thread every time the
    /// user types a character in the call field — including when nothing is
    /// being sent. Must never trap on empty/short `pieces` or `envelope`.
    public func updateCallInMessage(_ aCall: String) -> Bool {
        if aCall.isEmpty { return false }
        var newEnvelope: [Float] = []
        var result = !pieces.isEmpty && pieces[0] == "@"

        if result {
            // Build the envelope for the new call and compare with the one
            // currently being played.
            Keyer.wpm = wpm
            Keyer.morseMsg = Keyer.encode(aCall)
            newEnvelope = Keyer.envelope
            for i in 0..<newEnvelope.count {
                newEnvelope[i] *= amplitude
            }
            // The already-sent part must match. Guard against envelope being
            // shorter than sendPos (can happen mid-transition).
            result = newEnvelope.count >= sendPos && envelope.count >= sendPos
            if result {
                for i in 0..<sendPos {
                    if envelope[i] != newEnvelope[i] { result = false; break }
                }
            }
            if result {
                envelope = newEnvelope
                hisCall = aCall
            }
        }

        // Could not correct the in-flight message, but a later '@' piece exists.
        // NOTE: the original Pascal `for i:=1 to Pieces.Count-1` is a no-op when
        // Pieces.Count <= 1; Swift's `1..<count` would TRAP for count == 0, so
        // guard the range explicitly.
        if !result, pieces.count > 1 {
            for i in 1..<pieces.count {
                if pieces[i] == "@" {
                    result = true
                    hisCall = aCall
                    return result
                }
            }
        }
        return result
    }
}
