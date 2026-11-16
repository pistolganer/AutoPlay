import SwiftUI
import PhotosUI

@main
struct AutoPlayApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - Pantallas

enum Screen: Hashable {
    case dash, home, maps, music, phone
}

// MARK: - Apps reales que se abren desde el inicio

struct AppTile: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let colors: [Color]
    var screen: Screen? = nil
    var url: String? = nil        // esquema de la app instalada
    var fallback: String? = nil   // web / App Store si no está instalada
}

let appTiles: [AppTile] = [
    AppTile(name: "Mapas", symbol: "location.north.fill", colors: [.green, Color(red: 0.1, green: 0.6, blue: 0.3)], screen: .maps),
    AppTile(name: "Música", symbol: "music.note", colors: [.pink, .red], screen: .music),
    AppTile(name: "Teléfono", symbol: "phone.fill", colors: [.green, Color(red: 0.15, green: 0.75, blue: 0.3)], screen: .phone),
    AppTile(name: "Spotify", symbol: "dot.radiowaves.left.and.right", colors: [Color(red: 0.11, green: 0.73, blue: 0.33), Color(red: 0.05, green: 0.45, blue: 0.2)],
            url: "spotify://", fallback: "https://apps.apple.com/app/id324684580"),
    AppTile(name: "Google Maps", symbol: "mappin.and.ellipse", colors: [.white, Color(white: 0.85)],
            url: "comgooglemaps://", fallback: "https://apps.apple.com/app/id585027354"),
    AppTile(name: "Waze", symbol: "car.fill", colors: [Color(red: 0.5, green: 0.85, blue: 1), Color(red: 0.2, green: 0.65, blue: 0.95)],
            url: "waze://", fallback: "https://apps.apple.com/app/id323229106"),
    AppTile(name: "Apple Music", symbol: "music.quarternote.3", colors: [.pink, Color(red: 0.95, green: 0.2, blue: 0.35)],
            url: "music://", fallback: "https://music.apple.com"),
    AppTile(name: "Mensajes", symbol: "message.fill", colors: [.green, Color(red: 0.15, green: 0.7, blue: 0.3)],
            url: "sms:"),
    AppTile(name: "WhatsApp", symbol: "bubble.left.and.bubble.right.fill", colors: [Color(red: 0.15, green: 0.83, blue: 0.4), Color(red: 0.05, green: 0.55, blue: 0.3)],
            url: "whatsapp://", fallback: "https://apps.apple.com/app/id310633997"),
    AppTile(name: "Podcasts", symbol: "mic.fill", colors: [.purple, Color(red: 0.55, green: 0.2, blue: 0.85)],
            url: "podcasts://"),
]

// MARK: - Vista principal

struct ContentView: View {
    @StateObject private var nav = NavModel()
    @StateObject private var music = MusicModel()
    @State private var screen: Screen = .dash
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.openURL) private var openURL

    var body: some View {
        let landscape = vSize == .compact
        let layout = landscape ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 8))

        layout {
            if landscape { dock(vertical: true) }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 0.05))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            if !landscape { dock(vertical: false) }
        }
        .padding(8)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true   // la pantalla no se apaga
            nav.start()
            music.start()
        }
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case .dash:  DashboardScreen(nav: nav, music: music, openMaps: { screen = .maps }, openMusic: { screen = .music })
        case .home:  HomeScreen(open: open)
        case .maps:  MapScreen(nav: nav)
        case .music: MusicScreen(music: music)
        case .phone: PhoneScreen()
        }
    }

    private func open(_ tile: AppTile) {
        if let s = tile.screen { withAnimation(.easeInOut(duration: 0.2)) { screen = s }; return }
        openApp(tile.url, fallback: tile.fallback, openURL: openURL)
    }

    // Dock tipo CarPlay
    private func dock(vertical: Bool) -> some View {
        let items = Group {
            StatusBlock(vertical: vertical)
            Spacer(minLength: 8)
            dockButton(appTiles[0])
            dockButton(appTiles[1])
            dockButton(appTiles[2])
            if music.isPlaying, let art = music.artwork {
                Button { screen = .music } label: {
                    Image(uiImage: art).resizable().scaledToFill()
                        .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Spacer(minLength: 8)
            Button { withAnimation { screen = (screen == .dash ? .home : .dash) } } label: {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 24))
                    .frame(width: 52, height: 52)
                    .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        return Group {
            if vertical {
                VStack(spacing: 12) { items }.frame(width: 76).padding(.vertical, 14)
            } else {
                HStack(spacing: 12) { items }.frame(height: 72).padding(.horizontal, 14)
            }
        }
        .foregroundStyle(.white)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func dockButton(_ t: AppTile) -> some View {
        Button { open(t) } label: { AppIcon(tile: t, size: 52) }
    }
}

/// Abre una app real; si no está instalada, abre la alternativa (web o App Store).
func openApp(_ url: String?, fallback: String?, openURL: OpenURLAction) {
    guard let s = url, let u = URL(string: s) else {
        if let f = fallback, let fu = URL(string: f) { openURL(fu) }
        return
    }
    openURL(u) { accepted in
        if !accepted, let f = fallback, let fu = URL(string: f) { openURL(fu) }
    }
}

// MARK: - Inicio

// Iconos personalizados: mantén pulsado un icono → «Cambiar icono» y elige una imagen
// (por ejemplo, una captura del icono original). Se guardan en el iPhone.
@MainActor
final class IconStore: ObservableObject {
    static let shared = IconStore()
    @Published private(set) var version = 0
    private var cache: [String: UIImage] = [:]
    private var missing: Set<String> = []

    private func url(_ name: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("icono_\(name).png")
    }
    func image(for name: String) -> UIImage? {
        if let i = cache[name] { return i }
        if missing.contains(name) { return nil }
        if let d = try? Data(contentsOf: url(name)), let i = UIImage(data: d) { cache[name] = i; return i }
        missing.insert(name)
        return nil
    }
    func set(_ data: Data, for name: String) {
        guard let img = UIImage(data: data) else { return }
        let side = min(img.size.width, img.size.height)
        let scale = 240 / side
        let out = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).image { _ in
            img.draw(in: CGRect(x: -(img.size.width - side) / 2 * scale, y: -(img.size.height - side) / 2 * scale,
                                width: img.size.width * scale, height: img.size.height * scale))
        }
        try? out.pngData()?.write(to: url(name))
        cache[name] = out
        missing.remove(name)
        version += 1
    }
    func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(name))
        cache[name] = nil
        missing.insert(name)
        version += 1
    }
}

struct AppIcon: View {
    let tile: AppTile
    var size: CGFloat = 74
    @ObservedObject private var store = IconStore.shared
    var body: some View {
        if let img = store.image(for: tile.name) {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        } else {
            defaultIcon
        }
    }
    private var defaultIcon: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: tile.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: tile.symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(tile.name == "Google Maps" ? Color.red : .white)
            )
    }
}

struct HomeScreen: View {
    let open: (AppTile) -> Void
    @State private var editing: AppTile?
    @State private var showPicker = false
    @State private var pick: PhotosPickerItem?
    private let cols = [GridItem(.adaptive(minimum: 96), spacing: 12)]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 22) {
                ForEach(appTiles) { t in
                    Button { open(t) } label: {
                        VStack(spacing: 8) {
                            AppIcon(tile: t)
                            Text(t.name).font(.system(size: 13)).foregroundStyle(Color(white: 0.9)).lineLimit(1)
                        }
                    }
                    .buttonStyle(PressStyle())
                    .contextMenu {
                        Button { editing = t; showPicker = true } label: { Label("Cambiar icono", systemImage: "photo") }
                        if IconStore.shared.image(for: t.name) != nil {
                            Button(role: .destructive) { IconStore.shared.remove(t.name) } label: { Label("Quitar icono", systemImage: "trash") }
                        }
                    }
                }
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .photosPicker(isPresented: $showPicker, selection: $pick, matching: .images)
        .onChange(of: pick) {
            guard let item = pick, let t = editing else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    IconStore.shared.set(data, for: t.name)
                }
                pick = nil
            }
        }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Hora, cobertura y batería (como en CarPlay)

struct StatusBlock: View {
    let vertical: Bool
    @State private var battery: Float = -1
    var body: some View {
        let stack = vertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 10))
        TimelineView(.periodic(from: .now, by: 10)) { ctx in
            stack {
                Text(ctx.date, format: .dateTime.hour().minute())
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                HStack(spacing: 3) {
                    Image(systemName: "cellularbars").font(.system(size: 12))
                    Text("5G").font(.system(size: 12, weight: .semibold))
                }
                Image(systemName: batteryIcon).font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                Circle().fill(.green).frame(width: 6, height: 6)
            }
            .onAppear {
                UIDevice.current.isBatteryMonitoringEnabled = true
                battery = UIDevice.current.batteryLevel
            }
            .onChange(of: ctx.date) { battery = UIDevice.current.batteryLevel }
        }
    }
    private var batteryIcon: String {
        switch battery {
        case ..<0:     return "battery.100"
        case ..<0.15:  return "battery.0"
        case ..<0.4:   return "battery.25"
        case ..<0.65:  return "battery.50"
        case ..<0.9:   return "battery.75"
        default:       return "battery.100"
        }
    }
}
