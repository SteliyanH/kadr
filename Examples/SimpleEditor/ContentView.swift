// SimpleEditor — Minimal SwiftUI app demonstrating Kadr
//
// This is a standalone example. To run it, create a new Xcode project,
// add Kadr as a local package dependency, and replace ContentView.swift
// with this file.

#if canImport(SwiftUI) && canImport(AVKit)
import SwiftUI
import AVKit
import Kadr

@available(iOS 16, macOS 13, *)
struct SimpleEditorView: View {
    @State private var selectedImage: PlatformImage?
    @State private var isExporting = false
    @State private var progress: Double = 0
    @State private var outputURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Kadr SimpleEditor")
                .font(.title)

            if let image = selectedImage {
                #if canImport(UIKit)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                #elseif canImport(AppKit)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                #endif
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .frame(height: 200)
                    .overlay {
                        Text("No image selected")
                            .foregroundStyle(.secondary)
                    }
            }

            if isExporting {
                ProgressView(value: progress)
                    .padding(.horizontal)
                Text("Exporting... \(Int(progress * 100))%")
                    .font(.caption)
            }

            if let outputURL {
                VideoPlayer(player: AVPlayer(url: outputURL))
                    .frame(height: 300)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Use Sample Image") {
                    // Create a simple colored image for demo
                    selectedImage = createSampleImage()
                }

                Button("Export Video") {
                    Task { await exportVideo() }
                }
                .disabled(selectedImage == nil || isExporting)
            }
        }
        .padding()
    }

    private func exportVideo() async {
        guard let image = selectedImage else { return }

        isExporting = true
        progress = 0
        errorMessage = nil
        outputURL = nil

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kadr_output")
            .appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: url)

        do {
            let exporter = Video {
                ImageClip(image, duration: 3.0)
            }
            .preset(.square)
            .exporter(to: url)

            for try await p in exporter.run() {
                progress = p.fractionCompleted
            }

            outputURL = url
        } catch {
            errorMessage = error.localizedDescription
        }

        isExporting = false
    }

    private func createSampleImage() -> PlatformImage {
        let size = CGSize(width: 1080, height: 1080)
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 72),
                .foregroundColor: UIColor.white
            ]
            let text = "Kadr" as NSString
            let textSize = text.size(withAttributes: attrs)
            let point = CGPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2
            )
            text.draw(at: point, withAttributes: attrs)
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: size))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 72),
            .foregroundColor: NSColor.white
        ]
        let text = "Kadr" as NSString
        let textSize = text.size(withAttributes: attrs)
        let point = CGPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2
        )
        text.draw(at: point, withAttributes: attrs)
        image.unlockFocus()
        return image
        #endif
    }
}
#endif
