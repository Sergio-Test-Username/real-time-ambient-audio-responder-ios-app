import SwiftUI

struct ContentView: View {
    @State private var audio = AudioController()
    @State private var showInfo = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header
                    listeningCard
                    metrics
                    responseCard
                    mixer
                    footer
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .sensoryFeedback(.impact(weight: .medium), trigger: audio.isRunning)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: audio.isRunning)
        .onChange(of: audio.volume) { _, _ in audio.updateMix() }
        .onChange(of: audio.automatic) { _, _ in audio.updateMix() }
        .onChange(of: audio.amounts) { _, _ in audio.updateMix() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { audio.stop() }
        }
        .alert("Audio access", isPresented: Binding(get: { audio.message != nil }, set: { if !$0 { audio.message = nil } })) {
            Button("OK") { audio.message = nil }
        } message: { Text(audio.message ?? "") }
        .sheet(isPresented: $showInfo) { information }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("ECHOLOOM")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(4).foregroundStyle(Theme.accent)
                Text("Sound, in conversation.")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
            }
            Spacer(minLength: 8)
            Button { showInfo = true } label: {
                Image(systemName: "info.circle").font(.title3)
                    .foregroundStyle(Theme.textSecondary).frame(width: 44, height: 44)
            }.accessibilityLabel("About live listening")
        }
    }

    private var listeningCard: some View {
        VStack(spacing: 20) {
            HStack {
                Label(audio.isRunning ? "LIVE ENVIRONMENT" : "YOUR ENVIRONMENT", systemImage: audio.isRunning ? "mic.fill" : "mic")
                    .font(.system(size: 10, weight: .bold)).tracking(1.5)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Circle().fill(audio.isRunning ? Color.green : Theme.textSecondary).frame(width: 6, height: 6)
                Text(audio.isRunning ? "ON DEVICE" : "READY").font(.system(size: 9, weight: .bold)).tracking(1)
                    .foregroundStyle(Theme.textSecondary)
            }
            ZStack {
                Circle().fill(Theme.accent.opacity(0.06)).frame(width: 224, height: 224)
                Circle().stroke(Theme.accent.opacity(0.12), lineWidth: 1).frame(width: 224, height: 224)
                Circle().stroke(Theme.accent.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 7])).frame(width: 194, height: 194)
                Circle().fill(Theme.accentGradient.opacity(0.15)).frame(width: 156, height: 156)
                    .scaleEffect(1 + audio.level * 0.2)
                VStack(spacing: 12) {
                    Image(systemName: audio.isRunning ? audio.scene.symbol : "waveform")
                        .font(.system(size: 35, weight: .light))
                        .foregroundStyle(audio.isRunning ? audio.scene.color : Theme.accent)
                        .contentTransition(.symbolEffect(.replace))
                    Text(audio.isRunning ? audio.scene.title : "Listen & respond")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text(audio.isRunning ? "\(Int(audio.elapsed) / 60):\(String(format: "%02d", Int(audio.elapsed) % 60)) · LIVE SESSION" : "A little space to tune in")
                        .font(.system(size: 9, weight: .medium)).tracking(1)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<32, id: \.self) { index in
                    Capsule().fill(Theme.accentGradient)
                        .frame(maxWidth: .infinity)
                        .frame(height: 4 + audio.bands[index] * 36)
                        .opacity(audio.isRunning ? 0.85 : 0.25)
                }
            }
            .frame(height: 40)
            .animation(.easeOut(duration: 0.16), value: audio.bands)
            Button { audio.toggle() } label: {
                HStack(spacing: 10) {
                    if audio.isStarting { ProgressView().tint(.white) }
                    else { Image(systemName: audio.isRunning ? "stop.fill" : "mic.fill") }
                    Text(audio.isStarting ? "Connecting microphone…" : (audio.isRunning ? "End session" : "Start listening"))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 17))
                .foregroundStyle(.white)
            }
            .disabled(audio.isStarting)
            Text("Headphones recommended to prevent audio feedback")
                .font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
        }
        .card()
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            metric("TEMPO", value: audio.isRunning && audio.tempoConfidence >= 0.2 ? "\(Int(audio.bpm.rounded()))" : "—", detail: "BPM · estimated", symbol: "metronome")
            metric("KEY", value: audio.isRunning && audio.keyConfidence >= 0.1 ? audio.key : "—", detail: "Tonal estimate", symbol: "pianokeys")
            metric("INPUT", value: audio.isRunning ? "\(Int(20 * log10(max(0.00001, audio.level / 8))))" : "—", detail: "dBFS", symbol: "waveform")
        }
    }

    private func metric(_ title: String, value: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title).tracking(1)
            }.font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(value).font(.system(size: 23, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
            Text(detail).font(.system(size: 9)).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Adaptive response", systemImage: "sparkles").font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Text("AUTO").font(.system(size: 9, weight: .bold)).tracking(1)
                    .foregroundStyle(audio.automatic ? Theme.accent : Theme.textSecondary)
                Toggle("Automatic response", isOn: $audio.automatic).labelsHidden().scaleEffect(0.8, anchor: .trailing)
            }
            Text(responseText).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineSpacing(4)
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.1.fill").font(.caption)
                Slider(value: $audio.volume, in: 0...0.85).accessibilityLabel("Output volume")
                Text("\(Int(audio.volume / 0.85 * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced)).frame(width: 34)
            }.foregroundStyle(Theme.accent)
        }.card()
    }

    private var responseText: String {
        if !audio.isRunning { return "Your surroundings lead. On-device listening shapes a continuous, complementary soundscape." }
        if !audio.automatic { return "You’re in control. Mix the layers below; tonal and beat layers wait for a confident key and tempo." }
        switch audio.scene {
        case .speech, .crowd: return "Making room for voices with a soft, unobtrusive texture. Rhythm steps back."
        case .music, .dj: return "Finding the pulse and tonal center. Beat and harmonic layers enter as confidence grows."
        case .birds, .wind, .water: return "Echoing the outdoors with procedural birdsong, gentle air and flowing water."
        default: return "Listening for a little more detail. A quiet nature texture holds the space."
        }
    }

    private var mixer: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("The layers").font(.system(size: 21, weight: .semibold, design: .rounded))
                Spacer()
                Text(audio.automatic ? "ADAPTIVE" : "MANUAL").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Theme.accent)
            }
            VStack(spacing: 0) {
                ForEach(MixLayer.allCases) { layer in
                    VStack(spacing: 0) {
                        HStack(spacing: 13) {
                            Image(systemName: layer.symbol).font(.system(size: 18)).foregroundStyle(Theme.accent)
                                .frame(width: 40, height: 42).background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(layer.title).font(.system(size: 14, weight: .medium))
                                Text(layer.rawValue >= 4 ? "Procedurally synthesized" : layer.caption)
                                    .font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer(minLength: 4)
                            if audio.automatic {
                                Text("AUTO").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(Theme.textSecondary).frame(height: 44)
                            } else {
                                Slider(value: Binding(get: { audio.amounts[layer.rawValue] }, set: { audio.amounts[layer.rawValue] = $0 }), in: 0...1)
                                    .frame(width: 104).accessibilityLabel("\(layer.title) level")
                            }
                        }.padding(.vertical, 11)
                        if layer != .water { Divider().overlay(Color.white.opacity(0.04)) }
                    }
                }
            }.padding(.horizontal, 16).background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Label("Private by nature", systemImage: "lock.shield")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
            Text("Audio stays on your device. Nothing recorded or uploaded.")
                .font(.system(size: 10)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }.padding(.top, 4)
    }

    private var information: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Image(systemName: "waveform.and.mic").font(.system(size: 44)).foregroundStyle(Theme.accent)
                        Text("A duet with your world.").font(.system(size: 30, weight: .semibold, design: .rounded))
                        infoSection("Listen locally", "Apple Sound Analysis recognizes music, speech, birds, wind and water on device. Microphone audio is never saved or uploaded.")
                        infoSection("An adaptive instrument", "Signal analysis estimates tempo and major/minor key. A synthesizer creates beats, bass, chords, arpeggios and nature textures continuously. Nature sounds are synthesized, not field recordings.")
                        infoSection("Give it a few seconds", "Steady, clear music gives the best estimates. This is a generative accompaniment, not source separation or a professional DJ beat grid. It does not identify DJ performances separately from music. Weak estimates keep musical layers silent.")
                        infoSection("Listen safely", "Use headphones at a comfortable volume. Speakers can feed the generated sound back into the microphone and affect detection. Listening ends when the app goes into the background.")
                    }.padding(24)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showInfo = false } } }
        }.preferredColorScheme(.dark)
    }

    private func infoSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(Theme.accent)
            Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary).lineSpacing(4)
        }
    }
}
