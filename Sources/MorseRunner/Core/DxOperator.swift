//
//  DxOperator.swift
//  Port of DxOper.pas — the DX station operator AI.
//
//  A finite-state machine that decides what the calling station sends next,
//  based on the messages it hears from "Me". Call-sign matching uses a small
//  dynamic-programming edit-distance with '?' wildcards.
//

import Foundation

let FULL_PATIENCE = 5

public enum OperatorState: Int {
    case needPrevEnd, needQso, needNr, needCall, needCallNr, needEnd, done, failed
}

public enum CallCheckResult: Int { case no, yes, almost }

public final class DxOperator {
    public var call: String = ""
    public var skills: Int = 1
    public var patience: Int = FULL_PATIENCE
    public var repeatCnt: Int = 1
    public var state: OperatorState = .needPrevEnd

    public init() {}

    // MARK: delays / derived values

    /// Delay before replying (in audio blocks), as a function of operator skill.
    public func getSendDelay() -> Int {
        if state == .needPrevEnd { return NEVER }
        if Settings.shared.runMode == .hst {
            return secondsToBlocks(0.05 + 0.5 * rnd() * 10.0 / Float(Settings.shared.wpm))
        }
        return secondsToBlocks(0.1 + 0.5 * rnd())
    }

    public func getWpm() -> Int {
        if Settings.shared.runMode == .hst { return Settings.shared.wpm }
        // If the user set a CW speed range, pick uniformly within [wpmLow, wpmHigh].
        // Otherwise use the original behaviour: wpm × 0.5~1.0 random.
        if Settings.shared.wpmLow > 0 && Settings.shared.wpmHigh > 0 {
            let lo = Settings.shared.wpmLow
            let hi = max(lo, Settings.shared.wpmHigh)
            return Int((Float(lo) + Float(hi - lo) * rnd()).rounded())
        }
        return Int((Float(Settings.shared.wpm) * 0.5 * (1 + rnd())).rounded())
    }

    public func getNR() -> Int {
        return 1 + Int((rnd() * Float(Tst.minute()) * Float(skills)).rounded())
    }

    public func getReplyTimeout() -> Int {
        var r: Int
        if Settings.shared.runMode == .hst {
            r = secondsToBlocks(Float(60) / Float(Settings.shared.wpm))
        } else {
            r = secondsToBlocks(Float(6 - skills))
        }
        return Int(rndGaussLim(Float(r), Float(r) / 2).rounded())
    }

    // MARK: patience

    private func decPatience() {
        if state == .done { return }
        patience -= 1
        if patience < 1 { state = .failed }
    }

    public func setState(_ newState: OperatorState) {
        state = newState
        if newState == .needQso {
            patience = Int(rndRayleigh(4).rounded())
        } else {
            patience = FULL_PATIENCE
        }
        if newState == .needQso, Settings.shared.runMode != .single, Settings.shared.runMode != .hst, rnd() < 0.1 {
            repeatCnt = 2
        } else {
            repeatCnt = 1
        }
    }

    // MARK: call-sign matching (IsMyCall)

    /// Dynamic-programming comparison of what "Me" sent (with '?' wildcards)
    /// against this operator's actual call.
    public func isMyCall() -> CallCheckResult {
        let wX = 2, wY = 2, wD = 2
        let c0 = Array(call)                       // this station's real call
        let c = Array(Tst.me.hisCall)        // what Me typed/sent

        // DP table M[x][y], x in 0...c.count, y in 0...c0.count
        var M = Array(repeating: Array(repeating: 0, count: c0.count + 1), count: c.count + 1)
        for y in 0...c0.count { M[0][y] = 0 }
        for x in 1...c.count { M[x][0] = M[x - 1][0] + wX }

        if c.count >= 1 {
            for x in 1...c.count {
                for y in 1...c0.count {
                    var t = M[x][y - 1]
                    // '?' matches more than one char; end may be missing
                    if x < c.count, c[x - 1] != "?" { t += wY }   // c[x] in Pascal is 1-based
                    var l = M[x - 1][y]
                    if c[x - 1] != "?" { l += wX }
                    var d = M[x - 1][y - 1]
                    if !(c[x - 1] == c0[y - 1] || c[x - 1] == "?") { d += wD }
                    M[x][y] = min(t, min(l, d))
                }
            }
        }

        let penalty = M[c.count][c0.count]
        var result: CallCheckResult
        switch penalty {
        case 0:     result = .yes
        case 1, 2:   result = .almost
        default:    result = .no
        }

        // callsign-specific corrections
        if !Settings.shared.lids, c.count == 2, result == .almost {
            result = .no
        }
        if result == .yes {
            if c.count != c0.count || c.contains("?") {
                result = .almost
            }
        }
        // partial / wildcard match too short
        let stripped = c.filter { $0 != "?" }
        if stripped.count < 2 {
            result = .no
        }
        // LIDS: occasionally accept a wrong call or reject the correct one
        if Settings.shared.lids, c.count > 3 {
            switch result {
            case .yes:
                if rnd() < 0.01 { result = .almost }
            case .almost:
                if rnd() < 0.04 { result = .yes }
            case .no:
                break
            }
        }
        return result
    }

    // MARK: message interpretation (MsgReceived)

    public func msgReceived(_ aMsg: StationMessages) {
        // CQ received → can call regardless of what else was sent
        if aMsg.contains(.cq) {
            switch state {
            case .needPrevEnd: setState(.needQso)
            case .needQso: decPatience()
            case .needNr, .needCall, .needCallNr: state = .failed
            case .needEnd: state = .done
            default: break
            }
            return
        }
        if aMsg.contains(.nilMsg) {
            switch state {
            case .needPrevEnd: setState(.needQso)
            case .needQso: decPatience()
            case .needNr, .needCall, .needCallNr, .needEnd: state = .failed
            default: break
            }
            return
        }

        if aMsg.contains(.hisCall) {
            switch isMyCall() {
            case .yes:
                switch state {
                case .needPrevEnd, .needQso: setState(.needNr)
                case .needCallNr: setState(.needNr)
                case .needCall: setState(.needEnd)
                default: break
                }
            case .almost:
                switch state {
                case .needPrevEnd, .needQso: setState(.needCallNr)
                case .needNr: setState(.needCallNr)
                case .needEnd: setState(.needCall)
                default: break
                }
            case .no:
                switch state {
                case .needQso: state = .needPrevEnd
                case .needNr, .needCall, .needCallNr: state = .failed
                case .needEnd: state = .done
                default: break
                }
            }
        }

        if aMsg.contains(.b4) {
            switch state {
            case .needPrevEnd, .needQso: setState(.needQso)
            case .needNr, .needEnd: state = .failed
            case .needCall, .needCallNr: break  // same state: correct the call
            default: break
            }
        }

        if aMsg.contains(.nr) {
            switch state {
            case .needPrevEnd: break
            case .needQso: state = .needPrevEnd
            case .needNr:
                if rnd() < 0.9 || Settings.shared.runMode == .hst { setState(.needEnd) }
            case .needCall: break
            case .needCallNr:
                if rnd() < 0.9 || Settings.shared.runMode == .hst { setState(.needCall) }
            case .needEnd: break
            default: break
            }
        }

        if aMsg.contains(.tu) {
            switch state {
            case .needPrevEnd: setState(.needQso)
            case .needQso, .needNr, .needCall, .needCallNr: break
            case .needEnd: state = .done
            default: break
            }
        }

        if !Settings.shared.lids, aMsg == .garbage {
            state = .needPrevEnd
        }

        if state != .needPrevEnd { decPatience() }
    }

    // MARK: reply (GetReply)

    public func getReply() -> StationMessage {
        switch state {
        case .needPrevEnd, .done, .failed:
            return .none
        case .needQso:
            return .myCall
        case .needNr:
            if patience == (FULL_PATIENCE - 1) || rnd() < 0.3 {
                return .nrQm
            } else {
                return .agn
            }
        case .needCall:
            if Settings.shared.runMode == .hst || rnd() > 0.5 {
                return .deMyCallNr1
            } else if rnd() > 0.25 {
                return .deMyCallNr2
            } else {
                return .myCallNr2
            }
        case .needCallNr:
            if Settings.shared.runMode == .hst || rnd() > 0.5 {
                return .deMyCall1
            } else {
                return .deMyCall2
            }
        case .needEnd:
            if patience < (FULL_PATIENCE - 1) {
                return .nr
            } else if Settings.shared.runMode == .hst || rnd() < 0.9 {
                return .r_nr
            } else {
                return .r_nr2
            }
        }
    }
}
