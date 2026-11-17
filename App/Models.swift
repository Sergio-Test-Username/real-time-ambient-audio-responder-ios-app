import Foundation

enum SceneKind: String, CaseIterable, Identifiable {
    case silence, speech, music, dj, birds, wind, water, crowd, ambient

    var id: String { rawValue }

    var title: String {
        switch self {
        case .silence: return "Quiet"
        case .speech: return "Speech"
        case .music: return "Music"
        case .dj: return "DJ Set"
        case .birds: return "Birdsong"
        case .wind: return "Wind"
        case .water: return "Water"
        case .crowd: return "Crowd"
        case .ambient: return "Ambient"
        }
    }

    var symbol: String {
        switch self {
        case .silence: return "moon.zzz.fill"
        case .speech: return "waveform.and.mic"
        case .music: return "music.note"
        case .dj: return "headphones"
        case .birds: return "bird.fill"
        case .wind: return "wind"
        case .water: return "drop.fill"
        case .crowd: return "person.3.fill"
        case .ambient: return "sparkles"
        }
    }
}

enum MixLayer: Int, CaseIterable, Identifiable {
    case drums, bass, harmony, pluck, birds, wind, water

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .drums: return "Beat"
        case .bass: return "Bass"
        case .harmony: return "Harmony"
        case .pluck: return "Arpeggio"
        case .birds: return "Birds"
        case .wind: return "Wind"
        case .water: return "Water"
        }
    }

    var caption: String {
        switch self {
        case .drums: return "Beat-matched"
        case .bass: return "Locked to key"
        case .harmony: return "Chord pad"
        case .pluck: return "In-key notes"
        case .birds: return "Key-tuned song"
        case .wind: return "Slow gusts"
        case .water: return "Stream and drops"
        }
    }

    var symbol: String {
        switch self {
        case .drums: return "metronome.fill"
        case .bass: return "waveform.path"
        case .harmony: return "pianokeys"
        case .pluck: return "sparkle"
        case .birds: return "bird.fill"
        case .wind: return "wind"
        case .water: return "drop.fill"
        }
    }
}

struct AudioSnapshot {
    var level: Float = 0
    var db: Float = -90
    var bands: [Float] = []
    var bpm: Double = 0
    var tempoConfidence: Float = 0
    var phaseSince: Double = 0
    var phaseFresh: Bool = false
    var keyIndex: Int = -1
    var keyConfidence: Float = 0
    var lowRatio: Float = 0
    var flatness: Float = 0
    var sceneScores: [SceneKind: Float] = [:]
}

struct MixPlan {
    var drums: Float = 0
    var bass: Float = 0
    var pad: Float = 0
    var pluck: Float = 0
    var birds: Float = 0
    var wind: Float = 0
    var water: Float = 0
    var birdRate: Float = 6
    var bubbles: Float = 5
    var style: Int = 0
}
