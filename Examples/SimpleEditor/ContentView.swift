// SimpleEditor — Minimal SwiftUI app demonstrating Kadr
//
// To run this example:
// 1. Create a new Xcode project (iOS App or macOS App)
// 2. Add Kadr as a local package dependency
// 3. Copy this file and the Resources/ folder into your project
// 4. Add resources to your target's "Copy Bundle Resources" build phase
//
// Bundled resources:
//   - sample_sunset.png, sample_ocean.png, sample_forest.png, sample_purple.png
//   - sample_audio.mp3
//   - sample_video.mp4

#if canImport(SwiftUI) && canImport(AVKit)
import SwiftUI
import AVKit
import Kadr

@available(iOS 16, macOS 13, *)
struct SimpleEditorView: View {
    @State private var isExporting = false
    @State private var progress: Double = 0
    @State private var outputURL: URL?
    @State private var errorMessage: String?
    @State private var selectedDemo: DemoType = .singleImage

    // Parametric controls (visible only for the demos that use them)
    @State private var slideDirection: SlideDirectionChoice = .fromRight
    @State private var speedRate: Double = 0.5
    @State private var duckingLevel: Double = 0.2
    @State private var stickerRotation: Double = -15      // degrees, -45...45
    @State private var watermarkCorner: WatermarkCorner = .bottomRight
    @State private var brightness: Double = 0.1            // -0.5...0.5
    @State private var cropFraction: Double = 0.7          // 0.3...1.0

    enum DemoType: String, CaseIterable, Identifiable {
        // v0.1
        case singleImage = "Image + Audio"
        case slideshow = "Slideshow"
        case trimVideo = "Trim Video"
        case mergeClips = "Merge Clips"
        case replaceAudio = "Replace Audio"
        // v0.2 — transitions
        case transitionFade = "Transition: Fade"
        case transitionDissolve = "Transition: Dissolve"
        case transitionSlide = "Transition: Slide"
        // v0.2 — speed
        case speed = "Speed Control"
        // v0.2 — audio ducking
        case ducking = "Audio Ducking"
        // v0.3 — overlays
        case imageOverlay = "Overlay: Image"
        case textOverlay = "Overlay: Text"
        case stickerOverlay = "Overlay: Sticker"
        case watermark = "Watermark"
        // v0.3 — filters
        case filterBrightness = "Filter: Brightness"
        case filterMono = "Filter: Mono"
        case filterChain = "Filter: Warm Grade"
        // v0.3 — layout
        case crop = "Crop"
        // v0.3 — sugar
        case backgroundMusic = "Background Music"
        case titleSequence = "Title Sequence"

        var id: Self { self }
    }

    enum SlideDirectionChoice: String, CaseIterable, Identifiable {
        case fromLeft, fromRight, fromTop, fromBottom
        var id: Self { self }
        var direction: SlideDirection {
            switch self {
            case .fromLeft: return .fromLeft
            case .fromRight: return .fromRight
            case .fromTop: return .fromTop
            case .fromBottom: return .fromBottom
            }
        }
    }

    enum WatermarkCorner: String, CaseIterable, Identifiable {
        case topLeft, topRight, bottomLeft, bottomRight
        var id: Self { self }
        var position: Position {
            switch self {
            case .topLeft: return .topLeft
            case .topRight: return .topRight
            case .bottomLeft: return .bottomLeft
            case .bottomRight: return .bottomRight
            }
        }
    }

    private let sampleNames = ["sample_sunset", "sample_ocean", "sample_forest", "sample_purple"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Kadr SimpleEditor")
                    .font(.title.bold())

                // Preview grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(sampleNames, id: \.self) { name in
                        let image = loadSampleImage(named: name)
                        #if canImport(UIKit)
                        SwiftUI.Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            .cornerRadius(8)
                        #elseif canImport(AppKit)
                        SwiftUI.Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            .cornerRadius(8)
                        #endif
                    }
                }
                .padding(.horizontal)

                // Demo picker — sectioned by category
                Picker("Demo", selection: $selectedDemo) {
                    Section("v0.1 Basics") {
                        ForEach([DemoType.singleImage, .slideshow, .trimVideo, .mergeClips, .replaceAudio]) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Section("v0.2 Transitions") {
                        ForEach([DemoType.transitionFade, .transitionDissolve, .transitionSlide]) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Section("v0.2 Effects") {
                        Text(DemoType.speed.rawValue).tag(DemoType.speed)
                        Text(DemoType.ducking.rawValue).tag(DemoType.ducking)
                    }
                    Section("v0.3 Overlays") {
                        ForEach([DemoType.imageOverlay, .textOverlay, .stickerOverlay, .watermark]) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Section("v0.3 Filters") {
                        ForEach([DemoType.filterBrightness, .filterMono, .filterChain]) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Section("v0.3 Layout & Sugar") {
                        Text(DemoType.crop.rawValue).tag(DemoType.crop)
                        Text(DemoType.backgroundMusic.rawValue).tag(DemoType.backgroundMusic)
                        Text(DemoType.titleSequence.rawValue).tag(DemoType.titleSequence)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)

                // Description
                Text(demoDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Parametric controls — only shown for the demos that use them
                parametricControls

                // Export button
                Button(action: { Task { await exportVideo() } }) {
                    HStack {
                        if isExporting { ProgressView().controlSize(.small) }
                        Text(isExporting ? "Exporting \(Int(progress * 100))%..." : "Export Video")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isExporting ? Color.gray : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isExporting)
                .padding(.horizontal)

                if isExporting {
                    ProgressView(value: progress).padding(.horizontal)
                }

                if let outputURL {
                    VideoPlayer(player: AVPlayer(url: outputURL))
                        .frame(height: 300)
                        .cornerRadius(10)
                        .padding(.horizontal)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    @ViewBuilder
    private var parametricControls: some View {
        if selectedDemo == .transitionSlide {
            Picker("Slide direction", selection: $slideDirection) {
                ForEach(SlideDirectionChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }

        if selectedDemo == .speed {
            sliderControl(label: "Speed", value: $speedRate, range: 0.25...4.0,
                          format: { "\($0, specifier: "%.2f")×" },
                          legend: "0.25 – 4.0")
        }

        if selectedDemo == .ducking {
            sliderControl(label: "Duck level", value: $duckingLevel, range: 0...1,
                          format: { "\(Int($0 * 100))%" },
                          legend: "0% (silent) – 100% (off)")
        }

        if selectedDemo == .stickerOverlay {
            sliderControl(label: "Rotation", value: $stickerRotation, range: -45...45,
                          format: { "\(Int($0))°" },
                          legend: "-45° – 45°")
        }

        if selectedDemo == .watermark {
            Picker("Corner", selection: $watermarkCorner) {
                ForEach(WatermarkCorner.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        }

        if selectedDemo == .filterBrightness {
            sliderControl(label: "Brightness", value: $brightness, range: -0.5...0.5,
                          format: { "\($0, specifier: "%+.2f")" },
                          legend: "-0.5 – 0.5")
        }

        if selectedDemo == .crop {
            sliderControl(label: "Crop fraction", value: $cropFraction, range: 0.3...1.0,
                          format: { "\(Int($0 * 100))%" },
                          legend: "30% – 100%")
        }
    }

    @ViewBuilder
    private func sliderControl(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: @escaping (Double) -> LocalizedStringKey,
        legend: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(label): ").font(.caption.monospacedDigit())
                    + Text(format(value.wrappedValue)).font(.caption.monospacedDigit())
                Spacer()
                Text(legend).font(.caption2).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
        .padding(.horizontal)
    }

    private var demoDescription: String {
        switch selectedDemo {
        // v0.1
        case .singleImage: return "Single image with background music exported as square video"
        case .slideshow:   return "4 images at 2s each with background music"
        case .trimVideo:   return "Trim sample video to 5–10 second range"
        case .mergeClips:  return "Merge a trimmed video clip with an image slide"
        case .replaceAudio: return "Mute the video and add new background music"
        // v0.2
        case .transitionFade:     return "Two image slides joined by a 0.5s fade-through-black"
        case .transitionDissolve: return "Two image slides cross-blended over 0.5s"
        case .transitionSlide:    return "Two video clips with a sliding transition (pick a direction above)"
        case .speed:              return "A 4-second video clip played back at the chosen speed multiplier (audio pitch preserved)"
        case .ducking:            return "Video with its own audio plus background music. Music ducks to the chosen level whenever the clip plays."
        // v0.3 Overlays
        case .imageOverlay:   return "Video with a corner image overlay"
        case .textOverlay:    return "Video with a centered text caption overlay at the bottom"
        case .stickerOverlay: return "Video with a rotated sticker (with drop shadow). Rotation is configurable above."
        case .watermark:      return "Video with a corner watermark using Video.watermark(...) sugar. Pick a corner above."
        // v0.3 Filters
        case .filterBrightness: return "Video with a brightness filter applied per-frame via CIColorControls"
        case .filterMono:       return "Video converted to black-and-white via CIPhotoEffectMono"
        case .filterChain:      return "Video with a warm color grade — brightness + contrast + saturation chained"
        // v0.3 Layout & Sugar
        case .crop:            return "Video cropped to a centered rectangular region (width and height as a fraction of the canvas)"
        case .backgroundMusic: return "Video with BackgroundMusic — defaults to volume 0.6, fades, ducking to 0.3 while clip audio plays"
        case .titleSequence:   return "Title card rendered in-engine, then the video clip — composed via the Video result-builder"
        }
    }

    // MARK: - Export

    private func exportVideo() async {
        isExporting = true
        progress = 0
        errorMessage = nil
        outputURL = nil

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kadr_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: url)

        do {
            let exporter = makeExporter(outputURL: url)
            for try await p in exporter.run() {
                progress = p.fractionCompleted
            }
            outputURL = url
        } catch {
            errorMessage = error.localizedDescription
        }

        isExporting = false
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func makeExporter(outputURL url: URL) -> Exporter {
        switch selectedDemo {
        // v0.1
        case .singleImage:
            return Video {
                ImageClip(loadSampleImage(named: "sample_sunset"), duration: 5.0)
            }
            .audio(url: sampleAudioURL)
            .preset(.square)
            .exporter(to: url)

        case .slideshow:
            return Video {
                ImageClip(loadSampleImage(named: "sample_sunset"), duration: 2.0)
                ImageClip(loadSampleImage(named: "sample_ocean"), duration: 2.0)
                ImageClip(loadSampleImage(named: "sample_forest"), duration: 2.0)
                ImageClip(loadSampleImage(named: "sample_purple"), duration: 2.0)
            }
            .audio(url: sampleAudioURL)
            .preset(.square)
            .exporter(to: url)

        case .trimVideo:
            return Video { VideoClip(url: sampleVideoURL).trimmed(to: 5...10) }
                .preset(.cinema)
                .exporter(to: url)

        case .mergeClips:
            return Video {
                VideoClip(url: sampleVideoURL).trimmed(to: 0...5)
                ImageClip(loadSampleImage(named: "sample_ocean"), duration: 3.0)
                VideoClip(url: sampleVideoURL).trimmed(to: 10...15)
            }
            .exporter(to: url)

        case .replaceAudio:
            return Video {
                VideoClip(url: sampleVideoURL).trimmed(to: 0...10).muted()
            }
            .audio(url: sampleAudioURL)
            .exporter(to: url)

        // v0.2
        case .transitionFade:
            return Video {
                ImageClip(loadSampleImage(named: "sample_sunset"), duration: 2.0)
                Transition.fade(duration: 0.5)
                ImageClip(loadSampleImage(named: "sample_ocean"), duration: 2.0)
            }
            .audio(url: sampleAudioURL)
            .preset(.square)
            .exporter(to: url)

        case .transitionDissolve:
            return Video {
                ImageClip(loadSampleImage(named: "sample_forest"), duration: 2.0)
                Transition.dissolve(duration: 0.5)
                ImageClip(loadSampleImage(named: "sample_purple"), duration: 2.0)
            }
            .audio(url: sampleAudioURL)
            .preset(.square)
            .exporter(to: url)

        case .transitionSlide:
            return Video {
                VideoClip(url: sampleVideoURL).trimmed(to: 0...3)
                Transition.slide(direction: slideDirection.direction, duration: 0.4)
                VideoClip(url: sampleVideoURL).trimmed(to: 5...8)
            }
            .preset(.cinema)
            .exporter(to: url)

        case .speed:
            return Video {
                VideoClip(url: sampleVideoURL).trimmed(to: 0...4).speed(speedRate)
            }
            .preset(.cinema)
            .exporter(to: url)

        case .ducking:
            return Video {
                VideoClip(url: sampleVideoURL).trimmed(to: 0...8)
            }
            .audio { AudioTrack(url: sampleAudioURL).volume(0.9).ducking(duckingLevel) }
            .preset(.cinema)
            .exporter(to: url)

        // v0.3 — Overlays
        case .imageOverlay:
            return Video {
                VideoClip(url: sampleVideoURL).trimmed(to: 0...5)
            }
            .overlay(
                ImageOverlay(loadSampleImage(named: "sample_sunset"))
                    .position(.topRight)
                    .anchor(.topRight)
                    .size(.normalized(width: 0.25, height: 0.25))
                    .opacity(0.9)
                    .id("badge")
            )
            .preset(.cinema)
            .exporter(to: url)

        case .textOverlay:
            return Video {
                VideoClip(url: sampleVideoURL).trimmed(to: 0...5)
            }
            .overlay(
                TextOverlay("HELLO FROM KADR",
                            style: TextStyle(fontSize: 64, color: .white, alignment: .center, weight: .bold))
                    .position(.bottom)
                    .anchor(.bottom)
                    .size(.normalized(width: 1.0, height: 0.2))
            )
            .preset(.cinema)
            .exporter(to: url)

        case .stickerOverlay:
            return Video {
                VideoClip(url: sampleVideoURL).trimmed(to: 0...5)
            }
            .overlay(
                StickerOverlay(loadSampleImage(named: "sample_purple"))
                    .position(.center)
                    .size(.normalized(width: 0.25, height: 0.25))
                    .rotation(degrees: stickerRotation)
                    .shadow(color: .black, radius: 14, offset: CGSize(width: 0, height: 6), opacity: 0.5)
            )
            .preset(.cinema)
            .exporter(to: url)

        case .watermark:
            return Video {
                VideoClip(url: sampleVideoURL).trimmed(to: 0...5)
            }
            .watermark(
                loadSampleImage(named: "sample_ocean"),
                position: watermarkCorner.position,
                size: .normalized(width: 0.15, height: 0.15),
                opacity: 0.6
            )
            .preset(.cinema)
            .exporter(to: url)

        // v0.3 — Filters
        case .filterBrightness:
            return Video {
                VideoClip(url: sampleVideoURL).trimmed(to: 0...5).filter(.brightness(brightness))
            }
            .preset(.cinema)
            .exporter(to: url)

        case .filterMono:
            return Video {
                VideoClip(url: sampleVideoURL).trimmed(to: 0...5).filter(.mono)
            }
            .preset(.cinema)
            .exporter(to: url)

        case .filterChain:
            return Video {
                VideoClip(url: sampleVideoURL).trimmed(to: 0...5)
                    .filter(.brightness(0.05), .contrast(1.15), .saturation(1.25))
            }
            .preset(.cinema)
            .exporter(to: url)

        // v0.3 — Layout & Sugar
        case .crop:
            return Video {
                VideoClip(url: sampleVideoURL).trimmed(to: 0...5)
            }
            .preset(.cinema)
            .crop(at: .center, size: .normalized(width: cropFraction, height: cropFraction))
            .exporter(to: url)

        case .backgroundMusic:
            return Video {
                VideoClip(url: sampleVideoURL).trimmed(to: 0...8)
            }
            .backgroundMusic(url: sampleAudioURL)
            .preset(.cinema)
            .exporter(to: url)

        case .titleSequence:
            return Video {
                TitleSequence("MY MOVIE",
                              duration: 2.0,
                              style: TextStyle(fontSize: 96, color: .white, alignment: .center, weight: .bold))
                Transition.fade(duration: 0.5)
                VideoClip(url: sampleVideoURL).trimmed(to: 0...4)
            }
            .preset(.cinema)
            .exporter(to: url)
        }
    }

    // MARK: - Resource URLs

    private var sampleVideoURL: URL {
        Bundle.main.url(forResource: "sample_video", withExtension: "mp4")
            ?? URL(fileURLWithPath: "sample_video.mp4")
    }

    private var sampleAudioURL: URL {
        Bundle.main.url(forResource: "sample_audio", withExtension: "mp3")
            ?? URL(fileURLWithPath: "sample_audio.mp3")
    }

    // MARK: - Image Loading

    private func loadSampleImage(named name: String) -> PlatformImage {
        #if canImport(UIKit)
        if let image = UIImage(named: name) { return image }
        #elseif canImport(AppKit)
        if let image = NSImage(named: name) { return image }
        #endif
        return generatePlaceholder(for: name)
    }

    private func generatePlaceholder(for name: String) -> PlatformImage {
        let colors: [String: (CGFloat, CGFloat, CGFloat)] = [
            "sample_sunset": (1.0, 0.37, 0.23),
            "sample_ocean": (0.0, 0.71, 0.85),
            "sample_forest": (0.22, 0.56, 0.24),
            "sample_purple": (0.56, 0.14, 0.67),
        ]
        let (r, g, b) = colors[name] ?? (0.5, 0.5, 0.5)
        let size = CGSize(width: 540, height: 540)

        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(red: r, green: g, blue: b, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(red: r, green: g, blue: b, alpha: 1).setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: size))
        image.unlockFocus()
        return image
        #endif
    }
}
#endif
