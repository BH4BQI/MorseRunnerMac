//
//  WavFile.swift
//  Port of WavFile.pas — minimal WAV writer (16-bit PCM mono).
//
//  The original used Windows mmio* APIs; we write a plain PCM/WAV file with
//  Foundation only. Audio is mono Float32 normalized to ±32767, written as
//  16-bit little-endian samples at DEFAULTRATE (11025 Hz).
//

import Foundation

public final class WavFile {
    public var fileName: String = ""
    public private(set) var isOpen: Bool = false

    private var fileHandle: FileHandle?
    private var dataSize: UInt32 = 0
    private var writeMode: Bool = false

    public var samplesPerSec: Int = DEFAULTRATE
    public var bytesPerSample: Int = 2

    public init() {}

    /// Open (create/truncate) the file for writing.
    public func openWrite() {
        guard !isOpen else { return }
        writeMode = true
        dataSize = 0
        let url = URL(fileURLWithPath: fileName)
        // truncate / create
        FileManager.default.createFile(atPath: url.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: url)

        // Write a placeholder header; we'll patch sizes on close.
        let header = makeHeader(dataSize: 0)
        fileHandle?.write(header)
        isOpen = true
    }

    public func close() {
        guard isOpen else { return }
        if writeMode {
            // patch the sizes in the header
            if let fh = fileHandle {
                let riffSize: UInt32 = 36 + dataSize
                fh.seek(toFileOffset: 4)
                fh.write(uint32LE(riffSize))
                fh.seek(toFileOffset: 40)
                fh.write(uint32LE(dataSize))
            }
        }
        try? fileHandle?.close()
        fileHandle = nil
        isOpen = false
        dataSize = 0
    }

    /// Append `count` Float32 samples (left channel; right ignored in mono).
    /// Mirrors WriteFrom(@LData, nil, count).
    public func write(from left: UnsafePointer<Float>, right: UnsafePointer<Float>?, count: Int) {
        guard isOpen, writeMode, count > 0 else { return }
        var bytes = [UInt8](repeating: 0, count: count * 2)
        for i in 0..<count {
            var v = Int(left[i].rounded())
            v = max(-32767, min(32767, v))
            let u = UInt16(bitPattern: Int16(truncatingIfNeeded: v))
            bytes[i * 2] = UInt8(u & 0xff)
            bytes[i * 2 + 1] = UInt8((u >> 8) & 0xff)
        }
        fileHandle?.write(Data(bytes))
        dataSize += UInt32(count * 2)
    }

    // MARK: header helpers

    private func makeHeader(dataSize: UInt32) -> Data {
        var d = Data()
        d.append(contentsOf: [0x52, 0x49, 0x46, 0x46])            // "RIFF"
        d.append(uint32LE(36 + dataSize))                          // chunk size
        d.append(contentsOf: [0x57, 0x41, 0x56, 0x45])            // "WAVE"
        d.append(contentsOf: [0x66, 0x6d, 0x74, 0x20])            // "fmt "
        d.append(uint32LE(16))                                     // subchunk size
        d.append(uint16LE(1))                                      // PCM
        d.append(uint16LE(1))                                      // mono
        d.append(uint32LE(UInt32(samplesPerSec)))
        d.append(uint32LE(UInt32(samplesPerSec * 2)))             // byte rate
        d.append(uint16LE(2))                                      // block align
        d.append(uint16LE(16))                                     // bits per sample
        d.append(contentsOf: [0x64, 0x61, 0x74, 0x61])            // "data"
        d.append(uint32LE(dataSize))
        return d
    }

    private func uint32LE(_ v: UInt32) -> Data {
        return Data([UInt8(v & 0xff), UInt8((v >> 8) & 0xff),
                     UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)])
    }

    private func uint16LE(_ v: UInt16) -> Data {
        return Data([UInt8(v & 0xff), UInt8((v >> 8) & 0xff)])
    }
}
