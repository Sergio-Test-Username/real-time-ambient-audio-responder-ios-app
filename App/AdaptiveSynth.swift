import AVFoundation

final class AdaptiveSynth {
    private let sampleRate: Double
    private let lock = NSLock()
    private var requestedGains = Array(repeating: Float(0), count: 7)
    private var requestedVolume: Float = 0
    private var requestedTempo = 90.0
    private var requestedKey = 0
    private var reset = false
    private var gains = Array(repeating: 0.0, count: 7)
    private var targets = Array(repeating: Float(0), count: 7)
    private var volume = 0.0
    private var targetVolume: Float = 0
    private var tempo = 90.0
    private var key = 0
    private var time = 0.0
    private var beat = 0.0
    private var noiseState: UInt32 = 123456789
    private var wind = 0.0
    private var water = 0.0
    private var phase = 0.0

    init(sampleRate: Double) { self.sampleRate = sampleRate }

    func update(gains: [Float], volume: Float, bpm: Double, key: Int, resetBeat: Bool) {
        lock.lock()
        requestedGains = gains
        requestedVolume = volume
        requestedTempo = bpm
        requestedKey = key
        reset = reset || resetBeat
        lock.unlock()
    }

    func render(frames: Int, buffers: UnsafeMutablePointer<AudioBufferList>) {
        if lock.try() {
            targets = requestedGains
            targetVolume = requestedVolume
            tempo = requestedTempo
            key = requestedKey
            if reset { beat = floor(beat); reset = false }
            lock.unlock()
        }
        let output = UnsafeMutableAudioBufferListPointer(buffers)
        let tau = Double.pi * 2
        let root = 65.4064 * pow(2, Double(key % 12) / 12)
        let third = key >= 12 ? 3.0 : 4.0
        let thirdRatio = pow(2, third / 12)
        let fifthRatio = pow(2, 7.0 / 12)
        let dt = 1 / sampleRate
        for frame in 0..<frames {
            time += dt
            beat += tempo / 60 * dt
            volume += (Double(targetVolume) - volume) * 0.0001
            for layer in 0..<7 { gains[layer] += (Double(targets[layer]) - gains[layer]) * 0.00004 }
            noiseState = 1664525 &* noiseState &+ 1013904223
            let noise = Double(noiseState) / Double(UInt32.max) * 2 - 1
            wind += (noise - wind) * 0.008
            water += (noise - water) * 0.12
            let fraction = beat - floor(beat)
            let beatSeconds = fraction * 60 / tempo
            let kick = sin(tau * (48 * beatSeconds + 6 * (1 - exp(-beatSeconds * 35)))) * exp(-beatSeconds * 16)
            let hatPhase = beat * 2 - floor(beat * 2)
            let hat = (noise - water) * exp(-hatPhase * 35) * 0.17
            let snare = Int(beat) % 2 == 1 ? noise * exp(-beatSeconds * 23) * 0.23 : 0
            let drums = (kick * 0.55 + hat + snare) * gains[0]
            phase += tau * root * dt
            if phase > tau { phase -= tau }
            let bass = (sin(phase) + sin(phase * 2) * 0.12) * exp(-fraction * 3) * gains[1] * 0.3
            let pad = (sin(tau * root * 2 * time) + sin(tau * root * 2 * thirdRatio * time) + sin(tau * root * 2 * fifthRatio * time)) / 3 * gains[2] * 0.22
            let step = Int(beat * 2) % 4
            let ratio = step == 1 ? thirdRatio : (step == 2 ? fifthRatio : (step == 3 ? 2 : 1))
            let pluck = sin(tau * root * 4 * ratio * time) * exp(-hatPhase * 7) * gains[3] * 0.15
            // Procedural nature textures: filtered turbulence, ripples and swept chirps.
            let gust = 0.55 + 0.3 * sin(time * 0.37) + 0.15 * sin(time * 0.91)
            let air = wind * gust * gains[5] * 2
            let ripples = sin(tau * 720 * time + 5 * sin(time * 2.7)) * pow(max(0, sin(time * 1.9)), 18) * 0.035
            let stream = (water * 0.18 + ripples) * gains[6]
            let birdCycle = time.truncatingRemainder(dividingBy: 5.7)
            let chirpPosition = birdCycle.truncatingRemainder(dividingBy: 0.24)
            let birdEnvelope = birdCycle < 0.94 ? pow(max(0, sin(Double.pi * chirpPosition / 0.24)), 3) : 0
            let birdFrequency = 2100.0
            let birdPhase = tau * (birdFrequency * time + 85 * sin(time * 17) + 14 * sin(time * 43))
            let birds = sin(birdPhase) * birdEnvelope * gains[4] * 0.09
            let sample = (drums + bass + pad + pluck + air + stream + birds) * volume
            let limited = Float(sample / (1 + abs(sample)))
            for buffer in output {
                guard let pointer = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let channelCount = Int(buffer.mNumberChannels)
                for channel in 0..<channelCount { pointer[frame * channelCount + channel] = limited }
            }
        }
    }
}
