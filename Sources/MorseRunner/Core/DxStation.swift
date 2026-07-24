//
//  DxStation.swift
//  Port of DxStn.pas — TDxStation.
//
//  A calling station with its own operator AI and QSB fading profile. Reacts to
//  events (timeouts, what "Me" sends) by transitioning its operator state and
//  replying with the appropriate CW message.
//

import Foundation

public final class DxStation: Station {
    public let oper = DxOperator()
    private var qsb: Qsb!

    public override init() {
        super.init()
        hisCall = Settings.shared.call
        myCall = PickCall()                         // the DX station's real call

        oper.call = myCall
        oper.skills = 1 + Int(rnd() * 3)            // 1..3
        oper.setState(.needPrevEnd)
        nrWithError = Settings.shared.lids && (rnd() < 0.1)

        wpm = oper.getWpm()
        nr = oper.getNR()
        if Settings.shared.lids && rnd() < 0.03 {
            rst = 559 + 10 * Int(rnd() * 4)
        } else {
            rst = 599
        }

        qsb = Qsb()
        qsb.bandwidth = 0.1 + rnd() / 2
        if Settings.shared.flutter && rnd() < 0.3 {
            qsb.bandwidth = 3 + rnd() * 30
        }

        amplitude = 9000 + 18000 * (1 + rndUShaped())
        pitch = Int(rndGaussLim(0, 300).rounded())

        timeout = NEVER
        state = .copying
    }

    public override func processEvent(_ event: StationEvent) {
        if oper.state == .done { return }

        switch event {
        case .msgSent:
            // we finished sending and started listening
            if Tst.me.state == .sending {
                timeout = NEVER
            } else {
                timeout = oper.getReplyTimeout()
            }

        case .timeout:
            // he did not reply, quit or try again
            if state == .listening {
                oper.msgReceived(.none)
                if oper.state == .failed { removeFromContest(); return }
                state = .preparingToSend
            }
            // preparations done, now send
            if state == .preparingToSend {
                for _ in 0..<oper.repeatCnt {
                    sendMsg(oper.getReply())
                }
            }

        case .meFinished:
            // notice the message only if we are not sending ourselves
            if state != .sending {
                switch state {
                case .copying:
                    oper.msgReceived(Tst.me.msg)
                case .listening, .preparingToSend:
                    // these messages can be copied even if partially received
                    let m = Tst.me.msg
                    if m.contains(.cq) || m.contains(.tu) || m.contains(.nilMsg) {
                        oper.msgReceived(m)
                    } else {
                        oper.msgReceived(.garbage)
                    }
                default:
                    break
                }
                // react
                if oper.state == .failed {
                    removeFromContest(); return
                } else {
                    timeout = oper.getSendDelay()
                }
                state = .preparingToSend
            }

        case .meStarted:
            // If we are not sending, we can start copying. Cancel timeout.
            if state != .sending {
                state = .copying
            }
            timeout = NEVER
        }
    }

    /// Copy our true call/RST/NR into the matching QSO record (found by call),
    /// recompute its err flag, then leave the pile-up. Thread-safe.
    public func dataToLastQso() {
        let idx = QsoLog.shared.updateLastTrueCall(myCall, rst: rst, nr: nr)
        if let i = idx { QsoLog.shared.checkErr(at: i) }
        removeFromContest()
    }

    public override func getBlock() -> [Float] {
        var block = super.getBlock()
        if Settings.shared.qsb { qsb.apply(to: &block) }
        return block
    }

    /// Remove this station from the contest's collection.
    private func removeFromContest() {
        Tst.stations.remove(self)
    }
}
