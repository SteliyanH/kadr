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

    // Parametric controls for v0.2 demos
    @State private var slideDirection: SlideDirectionChoice = .fromRight
    @State private var speedRate: Double = 0.5
    @State private var duckingLevel: Double = 0.2

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

        var id: Self { self }

        var category: String {
            switch self {
            case .singleImage, .slideshow, .trimVideo, .mergeClips, .replaceAudio:
                return "v0.1 Basics"
            case .transitionFade, .transitionDissolve, .transitionSlide:
                return "v0.2 Transitions"
            case .speed:
                return "v0.2 Speed"
            case .ducking:
                return "v0.2 Audio"
            }
        }
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
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            .cornerRadius(8)
                        #elseif canImport(AppKit)
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 100)
                            .cornerRadius(8)
                        #endif
                    }
                }
                .padding(.horizontal)

                // Demo picker — menu style scales well past ~5 items
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
                if selectedDemo == .transitionSlide {
                    Picker("Slide direction", selection: $slideDirection) {
                        ForEach(SlideDirectionChoice.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                if selectedDemo == .speed {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Speed: \(speedRate, specifier: "%.2f")×")
                                .font(.caption.monospacedDigit())
                            Spacer()
                            Text("0.25 – 4.0").font(.caption2).foregroundStyle(.secondary)
                        }
                        Slider(value: $speedRate, in: 0.25...4.0)
                    }
                    .padding(.horizontal)
                }

                if selectedDemo == .ducking {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Duck level: \(Int(duckingLevel * 100))%")
                                .font(.caption.monospacedDigit())
                            Spacer()
                            Text("0% (silent) – 100% (off)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Slider(value: $duckingLevel, in: 0...1)
                    }
                    .padding(.horizontal)
                }

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

    private var demoDescription: String {
        switch selectedDemo {
        case .singleImage:
            return "Single image with background music exported as square video"
        case .slideshow:
            return "4 images at 2s each with background music"
        case .trimVideo:
            return "Trim sample video to 5–10 second range"
        case .mergeClips:
            return "Merge a trimmed video clip with an image slide"
        case .replaceAudio:
            return "Mute the video and add new background music"
        case .transitionFade:
            return "Two image slides joined by a 0.5s fade-through-black"
        case .transitionDissolve:
            return "Two image slides cross-blended over 0.5s"
        case .transitionSlide:
            return "Two video clips with a sliding transition (pick a direction above)"
        case .speed:
            return "A 4-second video clip played back at the chosen speed multiplier (audio pitch preserved)"
        case .ducking:
            return "Video with its own audio plus background music. Music ducks to the chosen level whenever the clip plays."
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
            let exporter: Exporter
            switch selectedDemo {
            case .singleImage:
                exporter = Video {
                    ImageClip(loadSampleImage(named: "sample_sunset"), duration: 5.0)
                }
                .audio(url: sampleAudioURL)
                .preset(.square)
                .exporter(to: url)

            case .slideshow:
                exporter = Video {
                    ImageClip(loadSampleImage(named: "sample_sunset"), duration: 2.0)
                    ImageClip(loadSampleImage(named: "sample_ocean"), duration: 2.0)
                    ImageClip(loadSampleImage(named: "sample_forest"), duration: 2.0)
                    ImageClip(loadSampleImage(named: "sample_purple"), duration: 2.0)
                }
                .audio(url: sampleAudioURL)
                .preset(.square)
                .exporter(to: url)

            case .trimVideo:
                exporter = Video {
                    VideoClip(url: sampleVideoURL).trimmed(to: 5...10)
                }
                .preset(.cinema)
                .exporter(to: url)

            case .mergeClips:
                exporter = Video {
                    VideoClip(url: sampleVideoURL).trimmed(to: 0...5)
                    ImageClip(loadSampleImage(named: "sample_ocean"), duration: 3.0)
                    VideoClip(url: sampleVideoURL).trimmed(to: 10...15)
                }
                .exporter(to: url)

            case .replaceAudio:
                exporter = Video {
                    VideoClip(url: sampleVideoURL).trimmed(to: 0...10).muted()
                }
                .audio(url: sampleAudioURL)
                .exporter(to: url)

            case .transitionFade:
                exporter = Video {
                    ImageClip(loadSampleImage(named: "sample_sunset"), duration: 2.0)
                    Transition.fade(duration: 0.5)
                    ImageClip(loadSampleImage(named: "sample_ocean"), duration: 2.0)
                }
                .audio(url: sampleAudioURL)
                .preset(.square)
                .exporter(to: url)

            case .transitionDissolve:
                exporter = Video {
                    ImageClip(loadSampleImage(named: "sample_forest"), duration: 2.0)
                    Transition.dissolve(duration: 0.5)
                    ImageClip(loadSampleImage(named: "sample_purple"), duration: 2.0)
                }
                .audio(url: sampleAudioURL)
                .preset(.square)
                .exporter(to: url)

            case .transitionSlide:
                exporter = Video {
                    VideoClip(url: sampleVideoURL).trimmed(to: 0...3)
                    Transition.slide(direction: slideDirection.direction, duration: 0.4)
                    VideoClip(url: sampleVideoURL).trimmed(to: 5...8)
                }
                .preset(.cinema)
                .exporter(to: url)

            case .speed:
                exporter = Video {
                    VideoClip(url: sampleVideoURL).trimmed(to: 0...4).speed(speedRate)
                }
                .preset(.cinema)
                .exporter(to: url)

            case .ducking:
                exporter = Video {
                    VideoClip(url: sampleVideoURL).trimmed(to: 0...8)
                }
                .audio { AudioTrack(url: sampleAudioURL).volume(0.9).ducking(duckingLevel) }
                .preset(.cinema)
                .exporter(to: url)
            }

            for try await p in exporter.run() {
                progress = p.fractionCompleted
            }
            outputURL = url
        } catch {
            errorMessage = error.localizedDescription
        }

        isExporting = false
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
