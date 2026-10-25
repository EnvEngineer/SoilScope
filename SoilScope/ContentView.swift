import ARKit
import SwiftUI

private enum Palette {
    static let background = Color(red: 0.985, green: 0.975, blue: 0.955)
    static let panel = Color.white
    static let accent = Color(red: 0.24, green: 0.28, blue: 0.23)
    static let ink = Color(red: 0.16, green: 0.17, blue: 0.15)
    static let muted = Color(red: 0.48, green: 0.48, blue: 0.44)
    static let border = Color(red: 0.88, green: 0.86, blue: 0.82)
}

struct ContentView: View {
    @EnvironmentObject private var scan: ScanModel
    @State private var tab = 0

    private var cameraIsLive: Bool { tab == 0 && scan.photo == nil }

    var body: some View {
        TabView(selection: $tab) {
            ScanScreen(openPlan: { tab = 1 })
                .tabItem { Label("Scan", systemImage: "viewfinder") }
                .tag(0)
            PlanScreen(scan: scan)
                .tabItem { Label("Water", systemImage: "drop") }
                .tag(1)
            SettingsScreen()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(2)
        }
        .tint(cameraIsLive ? .white : Palette.accent)
        .toolbarBackground(cameraIsLive ? Color.black : Palette.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background((cameraIsLive ? Color.black : Palette.background).ignoresSafeArea())
        .preferredColorScheme(cameraIsLive ? .dark : .light)
    }
}

private struct ScanScreen: View {
    @EnvironmentObject private var scan: ScanModel
    @FocusState private var referenceIsFocused: Bool
    let openPlan: () -> Void

    var body: some View {
        Group {
            if scan.photo == nil {
                liveCamera
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        captured
                        statusCard
                        if let value = scan.moistureVWC {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Soil moisture estimate")
                                        .font(.subheadline)
                                        .foregroundStyle(Palette.muted)
                                    Text(String(format: "%.1f%%", value))
                                        .font(.system(size: 54, weight: .bold, design: .rounded))
                                        .foregroundStyle(Palette.ink)
                                }
                                Spacer()
                                Text("VWC")
                                    .font(.caption.bold())
                                    .foregroundStyle(Palette.muted)
                            }
                            .padding(20)
                            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 22))
                            Text("Research estimate · Check with a soil probe before watering.")
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                            Button(action: openPlan) {
                                Label("See water plan", systemImage: "arrow.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(scan.photo == nil ? Color.black : Palette.background)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { referenceIsFocused = false }
                    .fontWeight(.semibold)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("SOILSCOPE")
                    .font(.caption.bold())
                    .tracking(3)
                    .foregroundStyle(Palette.accent)
                Spacer()
                Image(systemName: "waveform.path.ecg.rectangle")
                    .foregroundStyle(Palette.accent)
            }
            Text("Your soil, at a glance.")
                .font(.system(size: 29, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var liveCamera: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraSurface()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: .top)
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [12, 8]))
                .frame(width: 230, height: 230)
                .allowsHitTesting(false)
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.white)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 12) {
                Text("SOILSCOPE")
                    .font(.caption.bold())
                    .tracking(3)
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    Circle()
                        .fill(scan.isLiDARReady ? .green : .orange)
                        .frame(width: 9, height: 9)
                    Text(scan.liveLiDARStatus)
                        .lineLimit(2)
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.6), in: Capsule())
                Spacer(minLength: 8)
                HStack {
                    Spacer()
                    Button { scan.capture() } label: {
                        Circle()
                            .fill(Palette.background)
                            .frame(width: 60, height: 60)
                            .padding(5)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Capture image")
                    .disabled(!scan.hasCameraFrame)
                    .opacity(scan.hasCameraFrame ? 1 : 0.5)
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.68)],
                               startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()) { _ in
            scan.refreshLiveLiDARStatus()
        }
    }

    private var captured: some View {
        VStack(alignment: .leading, spacing: 14) {
            PointEditor()
                .frame(height: 430)
                .clipShape(RoundedRectangle(cornerRadius: 22))
            Text("Drag the corners around the plant and nearby soil.")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
            if scan.usesManualScale {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add scale")
                        .font(.headline)
                    Text("Mark both ends of a known length lying flat on the soil.")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                    ReferenceEditor()
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    HStack {
                        Text("A–B length")
                        Spacer()
                        TextField("cm", text: $scan.manualReferenceLengthCM)
                            .keyboardType(.decimalPad)
                            .focused($referenceIsFocused)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                        Text("cm")
                    }
                    if scan.selectionSizeM == nil {
                        Text("Enter A–B length to continue.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(14)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
            }
            if let size = scan.selectionSizeM {
                Text(String(format: "%.2f × %.2f m · %@",
                            size.width, size.height,
                            scan.usesManualScale ? "Manual scale" : "LiDAR"))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Palette.muted)
            }
            HStack(spacing: 12) {
                Button("Retake") { scan.retake() }
                    .buttonStyle(SecondaryButtonStyle())
                if scan.moistureVWC == nil {
                    Button {
                        referenceIsFocused = false
                        Task { await scan.predict() }
                    } label: {
                        Text(scan.isPredicting ? "Estimating…" : "Estimate")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(scan.isPredicting || !scan.selectionHasScale)
                }
            }
        }
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Palette.accent)
            Text(scan.status)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct PointEditor: View {
    @EnvironmentObject private var scan: ScanModel

    var body: some View {
        GeometryReader { geometry in
            if let photo = scan.photo {
                let scale = min(geometry.size.width / photo.size.width,
                                geometry.size.height / photo.size.height)
                let fit = CGSize(width: photo.size.width * scale,
                                 height: photo.size.height * scale)
                let origin = CGPoint(x: (geometry.size.width - fit.width) / 2,
                                     y: (geometry.size.height - fit.height) / 2)
                ZStack(alignment: .topLeading) {
                    Color.black
                    Image(uiImage: photo)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        .position(x: origin.x + fit.width / 2,
                                  y: origin.y + fit.height / 2)
                    if scan.points.count == 4 {
                        Path { path in
                            path.move(to: displayPoint(scan.points[0], origin: origin, fit: fit))
                            for index in 1..<4 {
                                path.addLine(to: displayPoint(scan.points[index], origin: origin, fit: fit))
                            }
                            path.closeSubpath()
                        }
                        .fill(Palette.accent.opacity(0.10))
                        Path { path in
                            path.move(to: displayPoint(scan.points[0], origin: origin, fit: fit))
                            for index in 1..<4 {
                                path.addLine(to: displayPoint(scan.points[index], origin: origin, fit: fit))
                            }
                            path.closeSubpath()
                        }
                        .stroke(Palette.accent, lineWidth: 2.5)
                        ForEach(0..<4, id: \.self) { index in
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Palette.accent, in: Circle())
                                .position(displayPoint(scan.points[index], origin: origin, fit: fit))
                                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("pointEditor"))
                                    .onChanged { value in
                                        scan.movePoint(index, to: CGPoint(
                                            x: (value.location.x - origin.x) / fit.width,
                                            y: (value.location.y - origin.y) / fit.height
                                        ))
                                    })
                        }
                    }
                }
                .coordinateSpace(name: "pointEditor")
            }
        }
    }

    private func displayPoint(_ point: CGPoint, origin: CGPoint, fit: CGSize) -> CGPoint {
        CGPoint(x: origin.x + point.x * fit.width,
                y: origin.y + point.y * fit.height)
    }
}

private struct ReferenceEditor: View {
    @EnvironmentObject private var scan: ScanModel

    var body: some View {
        GeometryReader { geometry in
            if let photo = scan.photo, scan.manualReferencePoints.count == 2 {
                let scale = min(geometry.size.width / photo.size.width,
                                geometry.size.height / photo.size.height)
                let fit = CGSize(width: photo.size.width * scale,
                                 height: photo.size.height * scale)
                let origin = CGPoint(x: (geometry.size.width - fit.width) / 2,
                                     y: (geometry.size.height - fit.height) / 2)
                let display: (CGPoint) -> CGPoint = { point in
                    CGPoint(x: origin.x + point.x * fit.width,
                            y: origin.y + point.y * fit.height)
                }
                ZStack(alignment: .topLeading) {
                    Color.black
                    Image(uiImage: photo)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        .position(x: origin.x + fit.width / 2,
                                  y: origin.y + fit.height / 2)
                    Path { path in
                        path.move(to: display(scan.manualReferencePoints[0]))
                        path.addLine(to: display(scan.manualReferencePoints[1]))
                    }
                    .stroke(.yellow, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                    ForEach(0..<2, id: \.self) { index in
                        Text(index == 0 ? "A" : "B")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 25, height: 25)
                            .background(.yellow, in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .position(display(scan.manualReferencePoints[index]))
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("referenceEditor"))
                                .onChanged { value in
                                    scan.moveReferencePoint(index, to: CGPoint(
                                        x: (value.location.x - origin.x) / fit.width,
                                        y: (value.location.y - origin.y) / fit.height
                                    ))
                                })
                    }
                }
                .coordinateSpace(name: "referenceEditor")
            }
        }
    }
}

private struct PlanScreen: View {
    @ObservedObject var scan: ScanModel
    @StateObject private var forecastModel = ForecastModel()
    @State private var crop: Crop = .other
    @State private var soil: Soil = .loam
    @State private var areaText = "1.0"
    @State private var efficiency = 0.80
    @FocusState private var areaIsFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Water")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                moistureCard
                inputCard
                forecastCard
                recommendationCard
                Text("Estimate only. Check soil moisture with a probe before watering.")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            .padding(20)
        }
        .background(Palette.background)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { areaIsFocused = false }
                    .fontWeight(.semibold)
            }
        }
    }

    private var moistureCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("SOIL MOISTURE")
                    .font(.caption.bold())
                    .tracking(1.6)
                    .foregroundStyle(Palette.accent)
                Text(scan.moistureVWC.map { String(format: "%.1f%% VWC", $0) } ?? "No scan yet")
                    .font(.title2.bold())
            }
            Spacer()
            Image(systemName: "camera.macro")
                .font(.title)
                .foregroundStyle(Palette.accent)
        }
        .padding(18)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Growing conditions").font(.headline)
            Picker("Plant", selection: $crop) {
                ForEach(Crop.allCases) { Text($0.title).tag($0) }
            }
            Picker("Soil", selection: $soil) {
                ForEach(Soil.allCases) { Text($0.title).tag($0) }
            }
            HStack {
                Text("Area")
                Spacer()
                TextField("m²", text: $areaText)
                    .keyboardType(.decimalPad)
                    .focused($areaIsFocused)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 75)
                Text("m²")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Watering efficiency · \(Int(efficiency * 100))%")
                Slider(value: $efficiency, in: 0.5...1, step: 0.05)
                    .tint(Palette.accent)
            }
        }
        .padding(18)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Local forecast").font(.headline)
                Spacer()
                Button { forecastModel.refresh() } label: {
                    Label("Refresh", systemImage: "location.fill")
                        .font(.caption.bold())
                }
                .foregroundStyle(Palette.accent)
            }
            if let weather = forecastModel.forecast {
                HStack {
                    metric("Rain", String(format: "%.1f mm", weather.rainMM))
                    metric("High", String(format: "%.0f°C", weather.highC))
                    metric("ET₀", String(format: "%.1f mm", weather.et0MM))
                }
                Text("Today · updated \(weather.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
            } else {
                Text(forecastModel.status)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(18)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(Palette.muted)
            Text(value).font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recommendationCard: some View {
        let area = Double(areaText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let plan: WaterAdvice? = {
            guard scan.selectionHasScale,
                  let vwc = scan.moistureVWC, let weather = forecastModel.forecast else { return nil }
            return WaterPlanner.calculate(vwc: vwc, forecast: weather, crop: crop,
                                          soil: soil, areaM2: area, efficiency: efficiency)
        }()
        return VStack(alignment: .leading, spacing: 10) {
            Text("WATER SUGGESTION")
                .font(.caption.bold())
                .tracking(1.5)
                .foregroundStyle(Palette.accent)
            if let plan {
                Text(plan.litres < 0.1 ? "Wait and recheck" : String(format: "About %.1f L", plan.litres))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text(String(format: "%.1f mm over %.2f m²", plan.depthMM, area))
                    .font(.subheadline)
                Text(String(format: "Possible range %.1f–%.1f L", plan.lowLitres, plan.highLitres))
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                if let high = forecastModel.forecast?.highC, high >= 27 {
                    Label("Hot today · check the soil first", systemImage: "sun.max")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                Text("Scan soil, load weather, and add an area.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct SettingsScreen: View {
    @EnvironmentObject private var scan: ScanModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("About")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Private by design")
                        .font(.caption.bold())
                        .tracking(1.5)
                        .foregroundStyle(Palette.accent)
                    Text("The photo is analyzed on your iPhone. No image is sent to a model server.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
                .padding(18)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 8) {
                    Label("What to know", systemImage: "info.circle")
                        .font(.headline)
                    Text("LiDAR or a manual reference sets image scale. The camera estimates moisture from visible soil; it does not measure water directly.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                    Text("This research model was trained on six vineyard images. It is not validated for other plants, soils, or phone photos. Verify with a probe before using the water suggestion.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
                .padding(18)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
            }
            .padding(20)
        }
        .background(Palette.background)
    }
}

private struct CameraSurface: UIViewRepresentable {
    @EnvironmentObject private var scan: ScanModel

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.automaticallyUpdatesLighting = true
        scan.sceneView = view
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }
        view.session.run(configuration)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        scan.sceneView = uiView
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ()) {
        uiView.session.pause()
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.72 : 1),
                        in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .background(Palette.panel.opacity(configuration.isPressed ? 0.70 : 1),
                        in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.border))
    }
}
