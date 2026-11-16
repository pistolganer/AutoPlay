import SwiftUI
import MediaPlayer

// MARK: - Música real (lo que suena en Apple Music / biblioteca del iPhone)

@MainActor
final class MusicModel: ObservableObject {
    let player = MPMusicPlayerController.systemMusicPlayer
    @Published var title = "Nada sonando"
    @Published var artist = "Abre Apple Music o Spotify"
    @Published var album = ""
    @Published var artwork: UIImage?
    @Published var isPlaying = false
    @Published var shuffle = false
    @Published var repeatOn = false
    @Published var hasItem = false

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        MPMediaLibrary.requestAuthorization { _ in
            Task { @MainActor in self.refresh() }
        }
        player.beginGeneratingPlaybackNotifications()
        let nc = NotificationCenter.default
        for name in [Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange,
                     .MPMusicPlayerControllerPlaybackStateDidChange] {
            nc.addObserver(forName: name, object: player, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        refresh()
    }

    func refresh() {
        let item = player.nowPlayingItem
        hasItem = item != nil
        title = item?.title ?? "Nada sonando"
        artist = item?.artist ?? "Abre Apple Music o Spotify"
        album = item?.albumTitle ?? ""
        artwork = item?.artwork?.image(at: CGSize(width: 600, height: 600))
        isPlaying = player.playbackState == .playing
        shuffle = player.shuffleMode != .off
        repeatOn = player.repeatMode != .none
    }

    var elapsed: TimeInterval { player.currentPlaybackTime.isFinite ? player.currentPlaybackTime : 0 }
    var duration: TimeInterval { player.nowPlayingItem?.playbackDuration ?? 0 }

    func toggle() {
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }
    func next() { player.skipToNextItem() }
    func previous() { elapsed > 3 ? player.skipToBeginning() : player.skipToPreviousItem() }
    func toggleShuffle() { player.shuffleMode = shuffle ? .off : .songs; shuffle.toggle() }
    func toggleRepeat() { player.repeatMode = repeatOn ? .none : .all; repeatOn.toggle() }
    func seek(_ fraction: Double) { if duration > 0 { player.currentPlaybackTime = duration * fraction } }

    /// Pone a sonar toda la biblioteca en aleatorio (para el comando de voz «pon música»).
    func playLibrary() {
        player.setQueue(with: MPMediaQuery.songs())
        player.shuffleMode = .songs
        player.play()
    }
}

func timeString(_ t: TimeInterval) -> String {
    guard t.isFinite, t > 0 else { return "0:00" }
    return "\(Int(t) / 60):" + String(format: "%02d", Int(t) % 60)
}

// MARK: - Tarjeta «Ahora suena» (como en la foto)

struct NowPlayingCard: View {
    @ObservedObject var music: MusicModel
    var onTap: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL
    private let pink = Color(red: 1, green: 0.27, blue: 0.45)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Artwork(image: music.artwork)
                    .frame(maxWidth: 140, maxHeight: 140)
                    .onTapGesture { onTap?() }
                VStack(alignment: .leading, spacing: 4) {
                    Text(music.title).font(.system(size: 19, weight: .bold)).lineLimit(2)
                    Text(music.artist).font(.system(size: 15)).foregroundStyle(Color(white: 0.85)).lineLimit(1)
                    if !music.album.isEmpty {
                        Text(music.album).font(.system(size: 14)).foregroundStyle(pink).lineLimit(1)
                    }
                    if !music.hasItem {
                        HStack {
                            Button("Spotify") { openApp("spotify://", fallback: "https://apps.apple.com/app/id324684580", openURL: openURL) }
                                .buttonStyle(.borderedProminent).tint(Color(red: 0.11, green: 0.73, blue: 0.33))
                            Button("Música") { music.playLibrary() }
                                .buttonStyle(.bordered)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let d = music.duration, e = min(music.elapsed, d)
                VStack(spacing: 4) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.25))
                            Capsule().fill(pink).frame(width: d > 0 ? g.size.width * e / d : 0)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { p in music.seek(p.x / g.size.width) }
                    }
                    .frame(height: 5)
                    HStack {
                        Text(timeString(e)); Spacer(); Text(timeString(d))
                    }
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(Color(white: 0.8))
                }
            }

            HStack {
                ctrl("shuffle", tint: music.shuffle ? pink : Color(white: 0.6), size: 20, action: { music.toggleShuffle() })
                Spacer()
                ctrl("backward.end.fill", size: 26, action: { music.previous() })
                Spacer()
                ctrl(music.isPlaying ? "pause.fill" : "play.fill", size: 38, action: { music.toggle() })
                Spacer()
                ctrl("forward.end.fill", size: 26, action: { music.next() })
                Spacer()
                ctrl("repeat", tint: music.repeatOn ? pink : Color(white: 0.6), size: 20, action: { music.toggleRepeat() })
            }
            .padding(.horizontal, 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.32), Color(red: 0.08, green: 0.07, blue: 0.2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func ctrl(_ symbol: String, tint: Color = .white, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint).frame(minWidth: 40, minHeight: 40)
        }
    }
}

struct Artwork: View {
    let image: UIImage?
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(red: 0.98, green: 0.18, blue: 0.3), Color(red: 0.48, green: 0.17, blue: 0.75)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").font(.system(size: 40)).foregroundStyle(.white))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Pantalla completa de música

struct MusicScreen: View {
    @ObservedObject var music: MusicModel
    var body: some View {
        VStack(spacing: 8) {
            NowPlayingCard(music: music)
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                VolumeSlider().frame(height: 34)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18).padding(.vertical, 6)
            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(8)
        .onAppear { music.refresh() }
    }
}

/// Volumen del sistema + botón AirPlay/Bluetooth para elegir el altavoz del coche.
struct VolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: .zero)
        v.tintColor = .white
        return v
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
