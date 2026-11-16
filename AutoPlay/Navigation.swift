import SwiftUI
import MapKit
import CoreLocation
import AVFoundation

// MARK: - Modelo de navegación (GPS real + rutas de Apple Maps)

@MainActor
final class NavModel: NSObject, ObservableObject, CLLocationManagerDelegate, AVSpeechSynthesizerDelegate {
    @Published var location: CLLocation?
    @Published var results: [MKMapItem] = []
    @Published var destination: MKMapItem?
    @Published var route: MKRoute?
    @Published var nextIndex = 1                       // próximo paso (maniobra)
    @Published var distanceToNext: CLLocationDistance = 0
    @Published var remaining: CLLocationDistance = 0
    @Published var voiceOn = true
    @Published var arrived = false

    private let lm = CLLocationManager()
    private let synth = AVSpeechSynthesizer()
    private var spokenFor = -1

    func start() {
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        lm.activityType = .automotiveNavigation
        lm.requestWhenInUseAuthorization()
        lm.startUpdatingLocation()
        lm.startUpdatingHeading()
        synth.delegate = self
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in self.update(l) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.lm.startUpdatingLocation() }
    }

    // Velocidad en km/h
    var speedKmh: Int { max(0, Int(((location?.speed ?? 0) * 3.6).rounded())) }

    var nextStep: MKRoute.Step? {
        guard let r = route, nextIndex < r.steps.count else { return nil }
        return r.steps[nextIndex]
    }

    var eta: Date? {
        guard let r = route, r.distance > 0 else { return nil }
        return Date().addingTimeInterval(r.expectedTravelTime * remaining / r.distance)
    }
    var minutesLeft: Int {
        guard let r = route, r.distance > 0 else { return 0 }
        return max(1, Int((r.expectedTravelTime * remaining / r.distance / 60).rounded()))
    }

    // MARK: Buscar

    func search(_ text: String) async {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = q
        if let c = location?.coordinate {
            req.region = MKCoordinateRegion(center: c, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        }
        results = (try? await MKLocalSearch(request: req).start().mapItems) ?? []
    }

    // MARK: Ruta

    func go(to item: MKMapItem) async {
        let req = MKDirections.Request()
        req.source = MKMapItem.forCurrentLocation()
        req.destination = item
        req.transportType = .automobile
        do {
            let resp = try await MKDirections(request: req).calculate()
            guard let r = resp.routes.first else { return }
            destination = item
            route = r
            arrived = false
            nextIndex = r.steps.count > 1 ? 1 : 0
            spokenFor = -1
            remaining = r.distance
            if let l = location { update(l) }
            speak("Iniciando ruta hacia \(item.name ?? "tu destino"). \(nextStep?.instructions ?? "")")
            spokenFor = nextIndex
        } catch {
            speak("No he podido calcular la ruta")
        }
    }

    func stop() {
        route = nil
        destination = nil
        synth.stopSpeaking(at: .immediate)
    }

    private func update(_ l: CLLocation) {
        location = l
        guard let r = route, let step = nextStep else { return }

        let start = step.polyline.points()[0].coordinate   // la maniobra ocurre al inicio del paso
        distanceToNext = l.distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude))

        // distancia restante = hasta la próxima maniobra + resto de pasos
        remaining = distanceToNext + r.steps[nextIndex...].reduce(0) { $0 + $1.distance }

        if distanceToNext < 25 {
            if nextIndex + 1 < r.steps.count {
                nextIndex += 1
            } else {
                arrived = true
                speak("Has llegado a tu destino")
                route = nil
                return
            }
        } else if distanceToNext < 250, spokenFor != nextIndex {
            spokenFor = nextIndex
            speak("En \(Self.format(distanceToNext)), \(step.instructions)")
        }
    }

    func speak(_ text: String) {
        guard voiceOn, !text.isEmpty else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "es-ES")
        // baja un poco la música (Spotify, Apple Music…) mientras habla
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
        try? session.setActive(true)
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.synth.isSpeaking {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }

    static func format(_ m: CLLocationDistance) -> String {
        m >= 1000 ? String(format: "%.1f km", m / 1000) : "\(Int((m / 10).rounded() * 10)) m"
    }

    static func icon(for text: String) -> String {
        let t = text.lowercased()
        if t.contains("destino") || t.contains("llegada") { return "flag.checkered" }
        if t.contains("rotonda") { return "arrow.triangle.turn.up.right.circle" }
        if t.contains("izquierda") { return t.contains("ligeramente") ? "arrow.up.left" : "arrow.turn.up.left" }
        if t.contains("derecha") { return t.contains("ligeramente") ? "arrow.up.right" : "arrow.turn.up.right" }
        if t.contains("media vuelta") || t.contains("cambio de sentido") { return "arrow.uturn.down" }
        return "arrow.up"
    }

    // Abrir la ruta en las apps reales
    func externalURL(_ app: String) -> (String, String)? {
        guard let c = destination?.placemark.coordinate else { return nil }
        let ll = "\(c.latitude),\(c.longitude)"
        switch app {
        case "google": return ("comgooglemaps://?daddr=\(ll)&directionsmode=driving",
                               "https://www.google.com/maps/dir/?api=1&destination=\(ll)&travelmode=driving")
        case "waze":   return ("waze://?ll=\(ll)&navigate=yes", "https://waze.com/ul?ll=\(ll)&navigate=yes")
        default:       return nil
        }
    }
}

// MARK: - Mapa real

struct MapScreen: View {
    @ObservedObject var nav: NavModel
    var compact = false                     // versión para el panel principal
    var onExpand: (() -> Void)? = nil
    @State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var showSearch = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Map(position: $position) {
                UserAnnotation()
                if let r = nav.route {
                    MapPolyline(r.polyline).stroke(.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                }
                if let d = nav.destination {
                    Marker(d.name ?? "Destino", coordinate: d.placemark.coordinate).tint(.red)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls { MapCompass() }

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    if let s = nav.nextStep, nav.route != nil {
                        maneuverCard(s)
                    }
                    Spacer()
                    if !compact { speedBubble }
                }
                Spacer()
                HStack(alignment: .bottom) {
                    Button { position = .userLocation(followsHeading: true, fallback: .automatic) } label: {
                        Image(systemName: "location.fill").font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                .padding(.bottom, 8)
                bottomBar
            }
            .padding(compact ? 10 : 12)
        }
        .sheet(isPresented: $showSearch) {
            SearchSheet(nav: nav) {
                showSearch = false
                position = .userLocation(followsHeading: true, fallback: .automatic)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func maneuverCard(_ s: MKRoute.Step) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: NavModel.icon(for: s.instructions))
                .font(.system(size: compact ? 30 : 38, weight: .bold))
                .frame(width: compact ? 40 : 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(NavModel.format(nav.distanceToNext))
                    .font(.system(size: compact ? 20 : 26, weight: .bold)).monospacedDigit()
                Text(s.instructions)
                    .font(.system(size: compact ? 14 : 16)).foregroundStyle(Color(white: 0.85))
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: compact ? 260 : 360, alignment: .leading)
        .background(Color(white: 0.08).opacity(0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var speedBubble: some View {
        VStack(spacing: 0) {
            Text("\(nav.speedKmh)").font(.system(size: 22, weight: .bold)).monospacedDigit()
            Text("km/h").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(width: 62, height: 62)
        .background(Color(white: 0.1).opacity(0.94), in: Circle())
        .overlay(Circle().stroke(.white, lineWidth: 3))
    }

    @ViewBuilder private var bottomBar: some View {
        HStack(spacing: 18) {
            if nav.route != nil, let eta = nav.eta {
                stat(eta.formatted(date: .omitted, time: .shortened), "llegada")
                stat("\(nav.minutesLeft)", "min")
                stat(NavModel.format(nav.remaining), "dist.")
                Spacer()
                if !compact {
                    Menu {
                        Button("Abrir en Google Maps") { openExternal("google") }
                        Button("Abrir en Waze") { openExternal("waze") }
                        Button(nav.voiceOn ? "Silenciar voz" : "Activar voz") { nav.voiceOn.toggle() }
                    } label: { Image(systemName: "ellipsis.circle").font(.system(size: 26)) }
                }
                Button { nav.stop() } label: {
                    Text("Fin").font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.red, in: Capsule())
                }
            } else {
                Button { showSearch = true } label: {
                    Label("¿A dónde vamos?", systemImage: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if compact, let onExpand {
                    Button(action: onExpand) { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 1) {
            Text(v).font(.system(size: 17, weight: .semibold)).monospacedDigit()
            Text(l).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func openExternal(_ app: String) {
        guard let pair = nav.externalURL(app) else { return }
        openApp(pair.0, fallback: pair.1, openURL: openURL)
    }
}

// MARK: - Buscador de destinos

struct SearchSheet: View {
    @ObservedObject var nav: NavModel
    var done: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    private let quick: [(String, String)] = [
        ("Gasolinera", "fuelpump.fill"), ("Aparcamiento", "parkingsign"),
        ("Restaurante", "fork.knife"), ("Supermercado", "cart.fill"), ("Cargador eléctrico", "bolt.car.fill")
    ]

    var body: some View {
        NavigationStack {
            List {
                if nav.results.isEmpty {
                    Section("Cerca de ti") {
                        ForEach(quick, id: \.0) { q in
                            Button { text = q.0; Task { await nav.search(q.0) } } label: {
                                Label(q.0, systemImage: q.1)
                            }
                        }
                    }
                }
                ForEach(nav.results, id: \.self) { item in
                    Button {
                        Task { await nav.go(to: item); done() }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Sin nombre").font(.headline)
                            Text(address(item)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar destino o dirección")
            .onSubmit(of: .search) { Task { await nav.search(text) } }
            .task(id: text) {
                try? await Task.sleep(for: .milliseconds(350))
                await nav.search(text)
            }
            .navigationTitle("Destino")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar", action: done) } }
        }
    }

    private func address(_ i: MKMapItem) -> String {
        let p = i.placemark
        return [p.thoroughfare, p.subThoroughfare, p.locality].compactMap { $0 }.joined(separator: " ")
    }
}
