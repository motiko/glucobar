import AppKit

/// The Urgent sound: an alarm-clock style pattern generated in code (no audio asset),
/// so it's unmistakable and distinct from every macOS system sound.
///
/// Pattern: 4 × (3 beeps of 110 ms, 60 ms apart), 380 ms between groups ≈ 3.5 s.
@MainActor
enum AlarmTone {
    /// Keeps the playing sound alive; NSSound stops when deallocated.
    private static var current: NSSound?
    private static let wav: Data = makeWAV()

    static func play() {
        current?.stop()
        guard let sound = NSSound(data: wav) else { return }
        sound.volume = 1.0 // full app volume (still scaled by the system output volume)
        current = sound
        sound.play()
    }

    // MARK: Synthesis

    private static let sampleRate = 44_100

    private static func makeWAV() -> Data {
        var samples: [Int16] = []
        for _ in 0..<4 {
            for beep in 0..<3 {
                // Alternate pitch slightly within a group, like a digital alarm clock.
                samples += tone(frequency: beep == 1 ? 3_100 : 2_700, seconds: 0.11)
                samples += silence(seconds: beep < 2 ? 0.06 : 0)
            }
            samples += silence(seconds: 0.38)
        }
        return wavFile(samples)
    }

    private static func tone(frequency: Double, seconds: Double) -> [Int16] {
        let count = Int(seconds * Double(sampleRate))
        let fade = Int(0.005 * Double(sampleRate)) // 5 ms ramps avoid clicks
        return (0..<count).map { i in
            let t = Double(i) / Double(sampleRate)
            // Fundamental plus a little 3rd harmonic for a harsher, more piercing timbre.
            var v = sin(2 * .pi * frequency * t) + 0.3 * sin(2 * .pi * 3 * frequency * t)
            v /= 1.3
            let envelope = min(1, Double(min(i, count - 1 - i)) / Double(fade))
            return Int16(v * envelope * 0.9 * Double(Int16.max))
        }
    }

    private static func silence(seconds: Double) -> [Int16] {
        Array(repeating: 0, count: Int(seconds * Double(sampleRate)))
    }

    /// 16-bit mono PCM WAV.
    private static func wavFile(_ samples: [Int16]) -> Data {
        var d = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let dataBytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + dataBytes))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(UInt32(sampleRate)); put(UInt32(sampleRate * 2)); put(UInt16(2)); put(UInt16(16))
        d.append(contentsOf: Array("data".utf8)); put(dataBytes)
        for s in samples { put(s) }
        return d
    }
}
