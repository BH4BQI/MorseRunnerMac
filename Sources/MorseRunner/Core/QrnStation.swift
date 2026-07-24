//
//  QrnStation.swift
//  Port of QrnStn.pas — TQrnStation (static / electrostatic noise burst).
//
//  A short noise burst (1 s on average) with sparse spikes. Self-destructs once
//  its envelope has been fully played.
//

import Foundation

public final class QrnStation: Station {
    public override init() {
        super.init()
        let dur = Int(Float(secondsToBlocks(rnd())) * Float(Settings.shared.bufSize))
        envelope = [Float](repeating: 0, count: dur)
        amplitude = 1e5 * powf(10, 2 * rnd())
        for i in 0..<envelope.count {
            if rnd() < 0.01 {
                envelope[i] = (rnd() - 0.5) * amplitude
            }
        }
        state = .sending
    }

    public override func processEvent(_ event: StationEvent) {
        if event == .msgSent {
            Tst.stations.remove(self)
        }
    }
}
