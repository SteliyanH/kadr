import Foundation
import KadrExamples

// Renders the README's GIFs into docs/media. Run from the repository root:
//
//     swift run KadrReadmeMedia            # every GIF
//     swift run KadrReadmeMedia hero pip   # only these
//
// Each GIF is the output of the snippet printed beside it in README.md; see
// Examples/ReadmeMedia/ReadmeMediaRenderer.swift.
let names = Set(CommandLine.arguments.dropFirst())
let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("docs/media", isDirectory: true)
try await ReadmeMediaRenderer.render(into: output, only: names)
