// Sounds: files in ~/.questlog/theme/sounds win; otherwise these original synthesized cues play.
import AVFoundation
import Foundation

@MainActor
final class Sound {
    static let shared = Sound()
    private var players: [AVAudioPlayer] = []
    private var synthCache: [String: Data] = [:]

    var muted: Bool { UserDefaults.standard.bool(forKey: "muted") }
    /// 0...100, low by default: these play while you work.
    var volume: Int { UserDefaults.standard.object(forKey: "volume") == nil ? 25 : UserDefaults.standard.integer(forKey: "volume") }

    func play(_ name: String) {
        guard !muted else { return }
        var player: AVAudioPlayer?
        if let url = Theme.shared.sounds[name] { player = try? AVAudioPlayer(contentsOf: url) }
        if player == nil, let data = synth(name) { player = try? AVAudioPlayer(data: data) }
        guard let player else { return }
        player.volume = Float(volume) / 100
        player.play()
        players.removeAll { !$0.isPlaying }
        players.append(player)
    }

    private func synth(_ name: String) -> Data? {
        if let d = synthCache[name] { return d }
        guard let d = Synth.cue(name) else { return nil }
        synthCache[name] = d
        return d
    }
}

/// Small offline synthesizer: bells, drums and filtered noise mixed into a WAV file in memory.
enum Synth {
    static let rate = 44_100.0

    struct Mix {
        var samples: [Float]
        init(seconds: Double) { samples = Array(repeating: 0, count: Int(seconds * Synth.rate)) }

        /// Exponential attack and decay envelope, like the WebAudio cues this replaced.
        static func env(_ t: Double, _ dur: Double, attack: Double) -> Double {
            if t < attack { return pow(10, -4 * (1 - t / attack)) }
            return pow(10, -4 * ((t - attack) / max(0.001, dur - attack)))
        }

        mutating func tone(_ freq: Double, at: Double, dur: Double, wave: String = "sine", gain: Double = 0.2, attack: Double = 0.008, glide: Double? = nil) {
            let start = Int(at * rate), n = Int(dur * rate)
            var phase = 0.0
            for i in 0..<n where start + i < samples.count {
                let t = Double(i) / rate
                let f = glide.map { freq * pow($0 / freq, t / dur) } ?? freq
                phase += f / rate
                let p = phase - floor(phase)
                let v: Double = switch wave {
                case "triangle": 4 * abs(p - 0.5) - 1
                case "sawtooth": 2 * p - 1
                default: sin(2 * .pi * p)
                }
                samples[start + i] += Float(v * gain * Mix.env(t, dur, attack: attack))
            }
        }

        mutating func bell(_ f: Double, at: Double, dur: Double, gain: Double) {
            tone(f, at: at, dur: dur, gain: gain)
            tone(f * 2.005, at: at, dur: dur * 0.55, gain: gain * 0.3)
            tone(f * 3.01, at: at, dur: dur * 0.3, wave: "triangle", gain: gain * 0.1)
        }

        /// Band-passed noise sweeping from `freq` to `to` (paper sliding, page turning).
        mutating func noise(at: Double, dur: Double, freq: Double = 1000, to: Double = 400, gain: Double = 0.12, q: Double = 0.9) {
            let start = Int(at * rate), n = Int(dur * rate)
            var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
            var rng = SystemRandomNumberGenerator()
            for i in 0..<n where start + i < samples.count {
                let t = Double(i) / rate
                let f0 = freq * pow(to / freq, t / dur)
                let w = 2 * .pi * f0 / rate, alpha = sin(w) / (2 * q)
                let b0 = alpha, a0 = 1 + alpha, a1 = -2 * cos(w), a2 = 1 - alpha
                let x = Double.random(in: -1...1, using: &rng)
                let y = (b0 * x - b0 * x2 - a1 * y1 - a2 * y2) / a0
                x2 = x1; x1 = x; y2 = y1; y1 = y
                samples[start + i] += Float(y * gain * Mix.env(t, dur, attack: dur * 0.15))
            }
        }

        mutating func drum(at: Double, gain: Double = 0.35) { tone(120, at: at, dur: 0.35, gain: gain, glide: 45) }

        func wav() -> Data {
            // Soft limit instead of normalising, so quiet cues stay quieter than big ones (like the WebAudio compressor did).
            let pcm = samples.map { Int16(tanh($0 * 1.6) / 1.1 * Float(Int16.max)) }
            var d = Data()
            func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
            func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
            d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + pcm.count * 2)); d.append(contentsOf: Array("WAVE".utf8))
            d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
            d.append(contentsOf: Array("data".utf8)); u32(UInt32(pcm.count * 2))
            pcm.forEach { u16(UInt16(bitPattern: $0)) }
            return d
        }
    }

    static func cue(_ name: String) -> Data? {
        var m: Mix
        switch name {
        case "open":
            m = Mix(seconds: 0.45); m.noise(at: 0, dur: 0.32, freq: 2400, to: 700, gain: 0.09); m.drum(at: 0.02, gain: 0.18)
        case "close":
            m = Mix(seconds: 0.4); m.noise(at: 0, dur: 0.22, freq: 900, to: 2000, gain: 0.07); m.drum(at: 0, gain: 0.12)
        case "offer":
            m = Mix(seconds: 1.4); m.noise(at: 0, dur: 0.3, freq: 2200, to: 800, gain: 0.07)
            m.bell(659, at: 0.05, dur: 0.9, gain: 0.09); m.bell(988, at: 0.18, dur: 1.1, gain: 0.08)
        case "accept":
            m = Mix(seconds: 1.3); m.drum(at: 0, gain: 0.4); m.tone(392, at: 0.04, dur: 0.45, wave: "sawtooth", gain: 0.035)
            m.bell(523, at: 0.06, dur: 0.8, gain: 0.12); m.bell(784, at: 0.2, dur: 1.0, gain: 0.12)
        case "objective":
            m = Mix(seconds: 0.75); m.bell(1175, at: 0, dur: 0.45, gain: 0.08); m.bell(1568, at: 0.07, dur: 0.6, gain: 0.06)
        case "complete":
            m = Mix(seconds: 2.0)
            for (i, t) in [0, 0.07, 0.14].enumerated() { m.drum(at: t, gain: 0.18 + Double(i) * 0.08) }
            for (i, f) in [523.0, 659, 784, 1047].enumerated() { m.bell(f, at: 0.18 + Double(i) * 0.1, dur: 1.4, gain: 0.12) }
            for (i, f) in [2093.0, 2637, 3136].enumerated() { m.tone(f, at: 0.6 + Double(i) * 0.06, dur: 0.8, gain: 0.025) }
        case "levelup":
            m = Mix(seconds: 2.6); m.drum(at: 0, gain: 0.45); m.drum(at: 0.12, gain: 0.35)
            for f in [392.0, 523, 659, 784] { m.tone(f, at: 0.1, dur: 2.2, wave: "triangle", gain: 0.06, attack: 0.25) }
            for (i, f) in [784.0, 988, 1175, 1568, 1976].enumerated() { m.bell(f, at: 0.25 + Double(i) * 0.09, dur: 1.6, gain: 0.09) }
        case "abandon":
            m = Mix(seconds: 0.6); m.tone(330, at: 0, dur: 0.5, wave: "triangle", gain: 0.12, glide: 220)
        default: return nil
        }
        return m.wav()
    }
}
