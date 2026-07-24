//
//  QrmStation.swift
//  Port of QrmStn.pas — TQrmStation (a QRM interferer running its own QSO).
//
//  Sends CQ/QRL/QSY-type messages and occasionally repeats; gives up after a
//  random number of attempts.
//

import Foundation

public final class QrmStation: Station {
    private var patience: Int = 0

    public override init() {
        super.init()
        patience = 1 + Int(rnd() * 5)
        myCall = PickCall()
        hisCall = Settings.shared.call
        amplitude = 5000 + 25000 * rnd()
        pitch = Int(rndGaussLim(0, 300).rounded())
        wpm = 30 + Int(rnd() * 20)

        switch Int(rnd() * 7) {
        case 0:    sendMsg(.qrl)
        case 1, 2: sendMsg(.qrl2)
        case 3, 4, 5: sendMsg(.longCQ)
        default:   sendMsg(.qsy)
        }
    }

    public override func processEvent(_ event: StationEvent) {
        switch event {
        case .msgSent:
            patience -= 1
            if patience == 0 {
                Tst.stations.remove(self)
            } else {
                timeout = Int(rndGaussLim(Float(secondsToBlocks(4)), 2).rounded())
            }
        case .timeout:
            sendMsg(.longCQ)
        default:
            break
        }
    }
}
