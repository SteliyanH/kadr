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

    enum DemoType: String, CaseIterable {
        case singleImage = "Image + Audio"
        case slideshow = "Slideshow"
        case trimVideo = "Trim Video"
        case mergeClips = "Merge Clips"
        case replaceAudio = "Replace Audio"
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

                // Demo picker
                Picker("Demo", selection: $selectedDemo) {
                    ForEach(DemoType.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Description
                Text(demoDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

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
            return "Trim sample video to 5-10 second range"
        case .mergeClips:
            return "Merge a trimmed video clip with an image slide"
        case .replaceAudio:
            return "Mute the video and add new background music"
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
