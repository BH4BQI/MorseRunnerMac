//
//  AudioEngine.swift
//  Port of SndOut.pas — real-time audio output.
//
//  Uses a Core Audio Output AudioUnit (Default Output). The render callback
//  pulls samples from a ring buffer that is continuously fed by the simulation
//  (Contest.getAudio), which always produces fixed `bufSize`-sample blocks at
//  the engine's native rate (11025 Hz). Core Audio inserts a sample-rate
//  converter (11025 → device rate) and may request an arbitrary number of
//  frames per callback; the ring buffer decouples that variable request size
//  from the simulation's fixed block size, so the CW waveform stays coherent.
//

import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation

public protocol AudioSampleProvider: AnyObject {
    /// Produce the next block of `count` Float32 samples (mono, 11025 Hz).
    func getAudio(count: Int) -> [Float]
}

/// Core Audio output engine. Fixed at 11025 Hz mono Float32 so the DSP
/// numerics match the original exactly; the hardware handles final conversion.
public final class AudioEngine {
    public weak var provider: AudioSampleProvider?

    private var audioUnit: AudioComponentInstance?
    public private(set) var isEnabled: Bool = false

    /// Ring buffer of samples fed by the provider and consumed by the realtime
    /// callback. Protected by `lock`; the callback holds it only briefly.
    private var ring: [Float]
    private var ringCount: Int { ring.count }
    private var readPos: Int = 0
    private var writePos: Int = 0
    private var lock = os_unfair_lock_s()

    /// How many samples to keep buffered ahead of the reader. ~0.4 s latency.
    private let targetFill = 4 * 1024

    public init() {
        ring = [Float](repeating: 0, count: 1 << 16)  // 64k ≈ 5.8 s @11 kHz
    }

    public var enabled: Bool {
        get { isEnabled }
        set { setEnabled(newValue) }
    }

    public func setEnabled(_ on: Bool) {
        if on == isEnabled { return }
        if on { start() } else { stop() }
    }

    private var ringCount_mod: Int { ring.count }
    private func posMod(_ a: Int) -> Int { a & (ring.count - 1) }
    private func available_unsafe() -> Int { (writePos - readPos) & (ring.count - 1) }

    /// Append a block of samples to the ring buffer (any thread).
    public func push(_ samples: [Float]) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        for s in samples {
            ring[writePos] = s
            writePos = posMod(writePos + 1)
            if writePos == readPos { readPos = posMod(readPos + 1) }  // full → drop oldest
        }
    }

    private func start() {
        os_unfair_lock_lock(&lock)
        readPos = 0
        writePos = 0
        os_unfair_lock_unlock(&lock)

        // Prefill so the first callback has data (avoids startup underrun).
        if let provider = provider {
            for _ in 0..<6 {
                push(provider.getAudio(count: 512))
            }
        }

        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_DefaultOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &desc) else { return }
        var instance: AudioComponentInstance?
        guard AudioComponentInstanceNew(component, &instance) == noErr,
              let au = instance else { return }
        audioUnit = au

        var streamFormat = AudioStreamBasicDescription(
            mSampleRate: Float64(DEFAULTRATE),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        AudioUnitSetProperty(au, kAudioUnitProperty_StreamFormat,
                             kAudioUnitScope_Input, 0, &streamFormat,
                             UInt32(MemoryLayout<AudioStreamBasicDescription>.size))

        var callbackStruct = AURenderCallbackStruct(
            inputProc: { (refCon, _, _, _, inNumberFrames, ioData) -> OSStatus in
                let engine = Unmanaged<AudioEngine>.fromOpaque(refCon).takeUnretainedValue()
                return engine.render(into: ioData, frames: Int(inNumberFrames))
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        AudioUnitSetProperty(au, kAudioUnitProperty_SetRenderCallback,
                             kAudioUnitScope_Input, 0, &callbackStruct,
                             UInt32(MemoryLayout<AURenderCallbackStruct>.size))

        guard AudioUnitInitialize(au) == noErr,
              AudioOutputUnitStart(au) == noErr else {
            AudioComponentInstanceDispose(au)
            audioUnit = nil
            return
        }
        isEnabled = true
    }

    private func stop() {
        guard let au = audioUnit else { return }
        AudioOutputUnitStop(au)
        AudioUnitUninitialize(au)
        AudioComponentInstanceDispose(au)
        audioUnit = nil
        isEnabled = false
    }

    deinit { stop() }

    // MARK: render

    /// Pull `frames` samples into the output buffer from the ring buffer, then
    /// top the ring up from the provider. Called on the realtime audio thread.
    /// Diagnostics (for verifying clean playback; harmless in production).
    public private(set) var underruns: Int = 0
    public private(set) var totalCallbacks: Int = 0

    @discardableResult
    private func render(into ioData: UnsafeMutablePointer<AudioBufferList>?,
                        frames: Int) -> OSStatus {
        guard let abl = ioData?.pointee else { return noErr }
        let buf = abl.mBuffers
        let outCap = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
        let n = min(frames, outCap)

        // Read from the ring under the lock.
        var starved = 0
        if n > 0, let dst = buf.mData?.assumingMemoryBound(to: Float.self) {
            os_unfair_lock_lock(&lock)
            for i in 0..<n {
                var s: Float = 0
                if writePos != readPos {
                    // provider returns ±32767-scale floats → normalize & clamp.
                    s = ring[readPos] / 32767.0
                    if s > 1 { s = 1 } else if s < -1 { s = -1 }
                    readPos = posMod(readPos + 1)
                } else {
                    starved += 1
                }
                dst[i] = s
            }
            os_unfair_lock_unlock(&lock)
        }
        totalCallbacks += 1
        if starved > 0 { underruns += 1 }

        // Keep the ring topped up from the provider (pull a few blocks).
        if let provider = provider {
            for _ in 0..<6 {
                os_unfair_lock_lock(&lock)
                let avail = (writePos - readPos) & (ring.count - 1)
                os_unfair_lock_unlock(&lock)
                if avail >= targetFill { break }
                push(provider.getAudio(count: 512))
            }
        }
        return noErr
    }
}
