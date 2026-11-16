import SwiftUI
import MapKit
import Speech
import AVFoundation

// MARK: - Panel principal (mapa + Ir/Voz + música), como en la foto

struct DashboardScreen: View {
    @ObservedObject var nav: NavModel
    @ObservedObject var music: MusicModel
    var openMaps: () -> Void
    var openMusic: () -> Void

    @StateObject private var voice = VoiceModel()
    @State private var showSearch = false
    @Environment(\.openURL) private var openURL
    @AppStorage("favoritos") private var favoritos = defaultFavorites
    @AppStorage("fuenteMusica") private var source = "spotify"
    @AppStorage("spotifySonando") private var spotifyPlaying = false

    var body: some View {
        GeometryReader { g in
            let landscape = g.size.width > g.size.height
            Group {
                if landscape {
                    HStack(spacing: 8) {
                        map.frame(width: g.size.width * 0.58)
                        VStack(spacing: 8) {
                            goVoice.frame(height: (g.size.height - 8) * 0.4)
                            NowPlayingCard(music: music, onTap: openMusic)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        map.frame(height: g.size.height * 0.45)
                        goVoice.frame(height: g.size.height * 0.17)
                        NowPlayingCard(music: music, onTap: openMusic)
                    }
                }
            }
        }
        .padding(8)
        .sheet(isPresented: $showSearch) {
            SearchSheet(nav: nav) { showSearch = false }
                .presentationDetents([.medium, .large])
        }
    }

    private var map: some View {
        MapScreen(nav: nav, compact: true, onExpand: openMaps)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // Tarjeta morada con «Ir» y «Voz»
    private var goVoice: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.22, green: 0.2, blue: 0.55), Color(red: 0.4, green: 0.25, blue: 0.65)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if voice.listening || !voice.text.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "waveform").font(.system(size: 30))
                        .symbolEffect(.variableColor.iterative, isActive: voice.listening)
                    Text(voice.text.isEmpty ? "Te escucho… «llévame a…», «pon música», «llama a…»" : voice.text)
                        .font(.system(size: 16, weight: .medium)).multilineTextAlignment(.center)
                        .lineLimit(3).padding(.horizontal)
                }
                .onTapGesture { voice.cancel() }
            } else {
                HStack {
                    Spacer()
                    roundButton("Ir", symbol: "arrow.triangle.turn.up.right.diamond.fill", color: .blue) { showSearch = true }
                    Spacer()
                    roundButton("Voz", symbol: "mic.fill", color: .red) { voice.start(onFinal: handleVoice) }
                    Spacer()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func roundButton(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 58, height: 58)
                    .background(color, in: Circle())
                Text(title).font(.system(size: 16, weight: .medium))
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(PressStyle())
    }

    // Comandos de voz
    private func handleVoice(_ raw: String) {
        let t = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }

        if source == "spotify" {
            if t.contains("pausa") || t.contains("para la música") {
                if spotifyPlaying { SpotifyRemote.run(SpotifyRemote.play, openURL: openURL); spotifyPlaying = false }
                return
            }
            if t.contains("siguiente") { SpotifyRemote.run(SpotifyRemote.next, openURL: openURL); return }
            if t.contains("anterior") { SpotifyRemote.run(SpotifyRemote.previous, openURL: openURL); return }
            if t.contains("pon música") || t.contains("reproduce") || t == "música" {
                if !spotifyPlaying { SpotifyRemote.run(SpotifyRemote.play, openURL: openURL); spotifyPlaying = true }
                return
            }
        }
        if t.contains("pausa") || t.contains("para la música") {
            if music.isPlaying { music.toggle() }; return
        }
        if t.contains("siguiente") { music.next(); return }
        if t.contains("pon música") || t.contains("reproduce") || t.contains("música") {
            if !music.hasItem { music.playLibrary() } else if !music.isPlaying { music.toggle() }
            return
        }
        if t.contains("spotify") {
            openApp("spotify://", fallback: "https://apps.apple.com/app/id324684580", openURL: openURL); return
        }
        if let r = t.range(of: "llama a ") {
            let name = String(t[r.upperBound...])
            if let c = parseFavorites(favoritos).first(where: { $0.name.lowercased().contains(name) || name.contains($0.name.lowercased()) }),
               let u = URL(string: "tel://\(c.digits)") {
                openURL(u)
            } else {
                nav.speak("No encuentro a \(name) en tus favoritos")
            }
            return
        }
        if t.contains("fin") && t.contains("ruta") { nav.stop(); return }

        // Cualquier otra cosa: destino
        var dest = t
        for p in ["llévame a ", "llevame a ", "vamos a ", "ir a ", "navega a ", "cómo llego a ", "como llego a "] {
            if let r = dest.range(of: p) { dest = String(dest[r.upperBound...]); break }
        }
        Task {
            await nav.search(dest)
            if let first = nav.results.first {
                await nav.go(to: first)
            } else {
                nav.speak("No he encontrado \(dest)")
            }
        }
    }
}

// MARK: - Reconocimiento de voz en español

@MainActor
final class VoiceModel: ObservableObject {
    @Published var listening = false
    @Published var text = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onFinal: ((String) -> Void)?

    func start(onFinal: @escaping (String) -> Void) {
        self.onFinal = onFinal
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else { return }
                AVAudioApplication.requestRecordPermission { ok in
                    Task { @MainActor in if ok { self.begin() } }
                }
            }
        }
    }

    private func begin() {
        finish(deliver: false)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { return }
        text = ""
        listening = true

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            let said = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            Task { @MainActor in
                guard let self else { return }
                if let said { self.text = said }
                if final || error != nil { self.finish(deliver: true) }
            }
        }
        // Deja de escuchar a los 5 segundos
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if self.listening { self.request?.endAudio() }
        }
    }

    func cancel() { onFinal = nil; finish(deliver: false); text = "" }

    private func finish(deliver: Bool) {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        task = nil
        let wasListening = listening
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if deliver, wasListening {
            let said = text
            onFinal?(said)
            onFinal = nil
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if !self.listening { self.text = "" }
            }
        }
    }
}

// MARK: - Teléfono

let defaultFavorites = "Mamá, 600 000 001\nPapá, 600 000 002\nTaller, 900 000 000"

struct Favorite: Identifiable {
    let id = UUID()
    let name: String
    let number: String
    var digits: String { number.filter { $0.isNumber || $0 == "+" } }
}

func parseFavorites(_ s: String) -> [Favorite] {
    s.split(separator: "\n").compactMap { line in
        let p = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return p.count == 2 && !p[0].isEmpty ? Favorite(name: p[0], number: p[1]) : nil
    }
}

struct PhoneScreen: View {
    @AppStorage("favoritos") private var favoritos = defaultFavorites
    @State private var number = ""
    @State private var editing = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { g in
            let layout = g.size.width > g.size.height ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 8))
            layout {
                favoritesList
                keypad
            }
        }
        .padding(8)
        .sheet(isPresented: $editing) {
            NavigationStack {
                VStack(alignment: .leading) {
                    Text("Un contacto por línea: Nombre, número").foregroundStyle(.secondary)
                    TextEditor(text: $favoritos).font(.body.monospaced())
                        .scrollContentBackground(.hidden).padding(8)
                        .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
                .navigationTitle("Favoritos")
                .toolbar { Button("Listo") { editing = false } }
            }
        }
    }

    private var favoritesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Favoritos").font(.title2.bold())
                Spacer()
                Button("Editar") { editing = true }
            }
            .padding(14)
            ScrollView {
                ForEach(parseFavorites(favoritos)) { f in
                    Button { call(f.digits) } label: {
                        HStack(spacing: 12) {
                            Text(String(f.name.prefix(1)))
                                .font(.headline).frame(width: 42, height: 42)
                                .background(Color(white: 0.25), in: Circle())
                            VStack(alignment: .leading) {
                                Text(f.name).font(.headline)
                                Text(f.number).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "phone.fill").foregroundStyle(.green)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                    }
                    .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var keypad: some View {
        let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]
        return VStack(spacing: 8) {
            Text(number.isEmpty ? " " : number)
                .font(.system(size: 28, weight: .medium)).monospacedDigit().lineLimit(1)
                .minimumScaleFactor(0.5)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(keys, id: \.self) { k in
                    Button { number += k } label: {
                        Text(k).font(.system(size: 24, weight: .medium))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .foregroundStyle(.white)
                }
            }
            HStack(spacing: 8) {
                Button { if !number.isEmpty { number.removeLast() } } label: {
                    Image(systemName: "delete.left").frame(maxWidth: .infinity, minHeight: 46)
                        .background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 12))
                }
                Button { call(number) } label: {
                    Label("Llamar", systemImage: "phone.fill").font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .foregroundStyle(.white)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func call(_ n: String) {
        let digits = n.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let u = URL(string: "tel://\(digits)") else { return }
        openURL(u)
    }
}
