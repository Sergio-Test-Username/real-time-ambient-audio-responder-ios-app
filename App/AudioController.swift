import Foundation
import AVFoundation
import SoundAnalysis
import Observation

@Observable
final class AudioController {
    var isRunning = false
    var isStarting = false
    var message: String?
    var scene: SceneKind = .silence
    var sceneConfidence: Double = 0
    var level: Double = 0
    var bands: [Double] = Array(repeating: 0.04, count: 32)
    var bpm: Double = 0
    var key = "—"
    var keyConfidence: Double = 0
    var tempoConfidence: Double = 0
    var automatic = true
    var volume: Float = 0.4
    var amounts: [Float] = [0.45, 0.3, 0.5, 0.25, 0.35, 0.25, 0.25]
    var elapsed: TimeInterval = 0

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var synth: AdaptiveSynth?
    @ObservationIgnored private var classifier: SceneClassifier?
    @ObservationIgnored private let analysisQueue = DispatchQueue(label: "audio.analysis", qos: .userInitiated)
    @ObservationIgnored private var interruption: NSObjectProtocol?
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var keyIndex = -1

    init() {
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stop()
            self?.message = "Audio interrupted. Tap Listen when you’re ready."
        }
    }

    deinit {
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
    }

    func toggle() {
        if isRunning { stop() } else if !isStarting {
            isStarting = true
            message = nil
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isStarting = false
                    if granted { self.start() }
                    else { self.message = "Microphone access is off. Enable it in Settings to listen and create a live mix." }
                }
            }
        }
    }

    private func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowBluetooth])
            try session.setPreferredIOBufferDuration(0.023)
            try session.setActive(true)
            let audioEngine = AVAudioEngine()
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw NSError(domain: "Audio", code: 1, userInfo: [NSLocalizedDescriptionKey: "No microphone is available. Connect an audio input and try again."])
            }
            let renderer = AdaptiveSynth(sampleRate: format.sampleRate)
            guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2) else { return }
            let source = AVAudioSourceNode(format: outputFormat) { _, _, count, list in
                renderer.render(frames: Int(count), buffers: list)
                return noErr
            }
            audioEngine.attach(source)
            audioEngine.connect(source, to: audioEngine.mainMixerNode, format: outputFormat)
            let analyzer = SNAudioStreamAnalyzer(format: format)
            let observer = SceneClassifier()
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48_000)
            request.overlapFactor = 0.5
            try analyzer.add(request, withObserver: observer)
            let id = UUID()
            sessionID = id
            observer.onScene = { [weak self] kind, confidence in
                DispatchQueue.main.async {
                    guard let self, self.isRunning, self.sessionID == id else { return }
                    self.scene = kind
                    self.sceneConfidence = confidence
                    self.updateMix()
                }
            }
            let meter = SignalTracker(sampleRate: format.sampleRate)
            let queue = analysisQueue
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, time in
                guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
                      let sourceChannels = buffer.floatChannelData, let targetChannels = copy.floatChannelData else { return }
                copy.frameLength = buffer.frameLength
                for channel in 0..<Int(buffer.format.channelCount) {
                    memcpy(targetChannels[channel], sourceChannels[channel], Int(buffer.frameLength) * MemoryLayout<Float>.size)
                }
                let position = time.sampleTime
                queue.async {
                    analyzer.analyze(copy, atAudioFramePosition: position)
                    guard let result = meter.process(copy) else { return }
                    DispatchQueue.main.async {
                        guard let self, self.isRunning, self.sessionID == id else { return }
                        self.level = result.level
                        self.bands = result.bands
                        self.bpm = result.bpm
                        self.tempoConfidence = result.tempoConfidence
                        self.keyIndex = result.keyIndex
                        self.keyConfidence = result.keyConfidence
                        self.key = result.keyIndex < 0 ? "—" : SignalTracker.keyName(result.keyIndex)
                        self.elapsed = result.elapsed
                        if result.level < 0.015 { self.scene = .silence; self.sceneConfidence = 0 }
                        self.updateMix(beatReset: result.beat)
                    }
                }
            }
            engine = audioEngine
            synth = renderer
            classifier = observer
            try audioEngine.start()
            isRunning = true
            updateMix()
        } catch {
            stop()
            message = error.localizedDescription
        }
    }

    func stop() {
        isRunning = false
        sessionID = UUID()
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        synth = nil
        classifier = nil
        level = 0
        bands = Array(repeating: 0.04, count: 32)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func updateMix(beatReset: Bool = false) {
        var gains = amounts
        if automatic {
            switch scene {
            case .music, .dj: gains = [0.6, 0.35, 0.4, 0.3, 0, 0.03, 0]
            case .speech, .crowd: gains = [0, 0, 0.12, 0, 0, 0.12, 0.08]
            case .birds: gains = [0, 0, 0.2, 0.08, 0.35, 0.25, 0.3]
            case .water: gains = [0, 0, 0.25, 0.12, 0.25, 0.1, 0.35]
            case .wind: gains = [0, 0, 0.3, 0, 0.2, 0.4, 0.1]
            case .silence, .ambient: gains = [0, 0, 0.2, 0.1, 0.15, 0.2, 0.15]
            }
        }
        // Never imply musical lock before there is enough evidence.
        if keyIndex < 0 || keyConfidence < 0.1 {
            gains[1] = 0; gains[2] = 0; gains[3] = 0
        }
        if tempoConfidence < 0.2 { gains[0] = 0 }
        synth?.update(gains: gains, volume: volume, bpm: bpm > 0 ? bpm : 90, key: max(0, keyIndex), resetBeat: beatReset && tempoConfidence > 0.2)
    }
}

private final class SceneClassifier: NSObject, SNResultsObserving {
    var onScene: ((SceneKind, Double) -> Void)?

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        var scores: [SceneKind: Double] = [:]
        for item in result.classifications {
            let name = item.identifier.lowercased()
            let kind: SceneKind
            if name.contains("speech") || name.contains("conversation") || name.contains("narration") { kind = .speech }
            else if name.contains("bird") || name.contains("chirp") { kind = .birds }
            else if name.contains("water") || name.contains("rain") || name.contains("stream") || name.contains("wave") { kind = .water }
            else if name.contains("wind") { kind = .wind }
            else if name.contains("crowd") || name.contains("applause") { kind = .crowd }
            else if name.contains("music") || name.contains("instrument") || name.contains("singing") || name.contains("drum") { kind = .music }
            else { continue }
            scores[kind, default: 0] += item.confidence
        }
        if let best = scores.max(by: { $0.value < $1.value }), best.value > 0.15 {
            onScene?(best.key, min(best.value, 1))
        } else { onScene?(.ambient, 0) }
    }
    func request(_ request: SNRequest, didFailWithError error: Error) {}
    func requestDidComplete(_ request: SNRequest) {}
}

private struct SignalReading {
    var level: Double
    var bands: [Double]
    var bpm: Double
    var tempoConfidence: Double
    var keyIndex: Int
    var keyConfidence: Double
    var elapsed: Double
    var beat: Bool
}

private final class SignalTracker {
    let sampleRate: Double
    var time: Double = 0
    var lastDisplay: Double = -1
    var average: Double = 0.01
    var lastOnset: Double = -10
    var intervals: [Double] = []
    var chroma = Array(repeating: 0.0, count: 12)
    var tempo: Double = 0
    var confidence: Double = 0
    var detectedKey = -1
    var keyConfidence: Double = 0
    var pendingBeat = false

    init(sampleRate: Double) { self.sampleRate = sampleRate }

    static func keyName(_ index: Int) -> String {
        let notes = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        return notes[index % 12] + (index >= 12 ? " min" : " maj")
    }

    func process(_ buffer: AVAudioPCMBuffer) -> SignalReading? {
        guard let samples = buffer.floatChannelData?[0] else { return nil }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return nil }
        time += Double(count) / sampleRate
        var energy = 0.0
        for i in 0..<count { energy += Double(samples[i] * samples[i]) }
        let rms = sqrt(energy / Double(count))
        if rms > max(0.012, average * 1.65), time - lastOnset > 0.28 {
            let interval = time - lastOnset
            if interval < 1.2 {
                intervals.append(interval)
                if intervals.count > 16 { intervals.removeFirst() }
                let sorted = intervals.sorted()
                let median = sorted[sorted.count / 2]
                let consistent = intervals.filter { abs($0 - median) < median * 0.16 }.count
                tempo = 60 / median
                confidence = min(1, Double(consistent) / 8)
            }
            lastOnset = time
            pendingBeat = true
        }
        average = average * 0.94 + rms * 0.06
        guard time - lastDisplay >= 0.16 else { return nil }
        lastDisplay = time
        if time - lastOnset > 4 { confidence *= 0.75 }
        var spectrum = Array(repeating: 0.0, count: 36)
        var frameChroma = Array(repeating: 0.0, count: 12)
        // Windowed Goertzel filter bank, covering three octaves of pitch classes.
        for note in 0..<36 {
            let frequency = 130.8128 * pow(2, Double(note) / 12)
            let coefficient = 2 * cos(2 * Double.pi * frequency / sampleRate)
            var first = 0.0
            var second = 0.0
            for i in 0..<count {
                let window = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(max(1, count - 1)))
                let current = Double(samples[i]) * window + coefficient * first - second
                second = first
                first = current
            }
            let magnitude = sqrt(max(0, first * first + second * second - coefficient * first * second)) / Double(count)
            spectrum[note] = magnitude
            frameChroma[note % 12] += magnitude
        }
        for i in 0..<12 { chroma[i] = chroma[i] * 0.88 + frameChroma[i] * 0.12 }
        let total = chroma.reduce(0, +)
        if rms > 0.008, total > 0.003 {
            let major = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
            let minor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
            var candidates: [(Int, Double)] = []
            let mean = total / 12
            for candidate in 0..<24 {
                let profile = candidate < 12 ? major : minor
                let profileMean = profile.reduce(0, +) / 12
                var score = 0.0
                var normA = 0.0
                var normB = 0.0
                for pitch in 0..<12 {
                    let a = chroma[pitch] - mean
                    let b = profile[(pitch - candidate % 12 + 12) % 12] - profileMean
                    score += a * b; normA += a * a; normB += b * b
                }
                candidates.append((candidate, score / max(0.000001, sqrt(normA * normB))))
            }
            candidates.sort { $0.1 > $1.1 }
            detectedKey = candidates[0].0
            keyConfidence = max(0, min(1, (candidates[0].1 - candidates[1].1) * 5))
        } else { detectedKey = -1; keyConfidence = 0 }
        let beat = pendingBeat
        pendingBeat = false
        let display = (0..<32).map { min(1, spectrum[$0] * 32) }
        return SignalReading(level: min(1, rms * 8), bands: display, bpm: tempo, tempoConfidence: confidence, keyIndex: detectedKey, keyConfidence: keyConfidence, elapsed: time, beat: beat)
    }
}
