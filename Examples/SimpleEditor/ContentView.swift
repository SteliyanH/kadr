// SimpleEditor — Minimal SwiftUI app demonstrating Kadr
//
// To run this example:
// 1. Create a new Xcode project (iOS App or macOS App)
// 2. Add Kadr as a local package dependency
// 3. Copy this file and the Resources/ folder into your project
// 4. Add the 4 sample PNGs to your asset catalog or bundle
// 5. (Optional) Add a .mp3 to Resources/ for audio demos
//
// Sample images included: sunset, ocean, forest, purple gradients
// For audio: https://pixabay.com/music/ (free, no attribution required)
// For video clips: https://www.pexels.com/videos/ (free)

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
        case singleImage = "Single Image"
        case slideshow = "Slideshow"
        case reelsPreset = "Reels"
    }

    private let sampleNames = ["sample_sunset", "sample_ocean", "sample_forest", "sample_purple"]

    var body: some View {
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
                    .frame(height: 250)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top)
    }

    // MARK: - Export

    private func exportVideo() async {
        isExporting = true
        progress = 0
        errorMessage = nil
        outputURL = nil

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kadr_\(selectedDemo.rawValue)")
            .appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: url)

        do {
            let exporter: Exporter
            switch selectedDemo {
            case .singleImage:
                exporter = Video {
                    ImageClip(loadSampleImage(named: "sample_sunset"), duration: 3.0)
                }
                .preset(.square)
                .exporter(to: url)

            case .slideshow:
                exporter = Video {
                    ImageClip(loadSampleImage(named: "sample_sunset"), duration: 2.0)
                    ImageClip(loadSampleImage(named: "sample_ocean"), duration: 2.0)
                    ImageClip(loadSampleImage(named: "sample_forest"), duration: 2.0)
                    ImageClip(loadSampleImage(named: "sample_purple"), duration: 2.0)
                }
                .preset(.square)
                .exporter(to: url)

            case .reelsPreset:
                exporter = Video {
                    ImageClip(loadSampleImage(named: "sample_ocean"), duration: 5.0)
                }
                .preset(.reelsAndShorts)
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

    // MARK: - Image Loading

    private func loadSampleImage(named name: String) -> PlatformImage {
        // Try loading from bundle (works when images are added to an Xcode project)
        #if canImport(UIKit)
        if let image = UIImage(named: name) { return image }
        #elseif canImport(AppKit)
        if let image = NSImage(named: name) { return image }
        #endif

        // Fallback: generate a colored placeholder
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
