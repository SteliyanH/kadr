import Kadr
import Foundation
import CoreMedia

/// v0.15–1.0 showcase — everything added between the last showcase and the
/// frozen API.
///
/// `Examples/` compiles as a target, which is the point of it: a snippet in a
/// README rots silently, and one in here fails the build. Five releases had
/// gone by without an example, so this file covers all of them.

// MARK: - Per-clip audio volume (v0.18)

/// Duck one clip under the others without touching the music bed.
///
/// Before v0.18 a clip's audio was all or nothing — `muted()`, or replaced
/// wholesale with `withAudio(_:)`. Every actual volume control lived on
/// `AudioTrack`, so "make this one clip quieter" was unreachable.
func v1_0_0_perClipVolume() -> Video {
    Video {
        VideoClip(url: URL(fileURLWithPath: "/tmp/interview.mov"))
            .trimmed(to: 0...12)

        // A noisy B-roll insert, dropped to a third so the narration carries.
        VideoClip(url: URL(fileURLWithPath: "/tmp/broll.mov"))
            .trimmed(to: 0...4)
            .volume(0.3)
    }
    .audio {
        AudioTrack(url: URL(fileURLWithPath: "/tmp/bed.m4a"))
            .volume(0.25)
            .ducking(0.1)      // and the bed still ducks under both
    }
}

// MARK: - Export quality (v0.20)

/// Export under a size limit, which `AVAssetExportSession` cannot express at all.
///
/// Its presets are the whole vocabulary, and the most specific thing they say is
/// "highest quality". Asking for 25 MB is not a preset, so kadr writes the
/// samples itself when a target is set — about twice the wall-clock of the
/// session path, and flat in bitrate. The default export is untouched.
func v1_0_0_exportUnderALimit() async throws -> URL {
    try await Video {
        VideoClip(url: URL(fileURLWithPath: "/tmp/scene.mov")).trimmed(to: 0...30)
    }
    .preset(.reelsAndShorts)
    .quality(.fileSize(bytes: 25_000_000))          // an upload limit
    .export(to: URL(fileURLWithPath: "/tmp/out.mp4"))
}

/// Or a bitrate directly, when the constraint is bandwidth rather than size.
func v1_0_0_exportAtABitrate() async throws -> URL {
    try await Video {
        VideoClip(url: URL(fileURLWithPath: "/tmp/scene.mov"))
    }
    .quality(.bitrate(4_000_000))                   // ~4 Mbps
    .export(to: URL(fileURLWithPath: "/tmp/out.mp4"))
}

// MARK: - The filter catalogue (v0.22)

/// Build an "add filter" menu that cannot go stale.
///
/// `Filter` has associated values, so it cannot be `CaseIterable` — there is no
/// `.brightness` to list, only `.brightness(0.2)`. Every UI that offered a
/// filter menu therefore hard-coded one, and every hard-coded menu silently
/// missed the next filter kadr added. `FilterKind` is the catalogue as a value.
func v1_0_0_filterMenu() -> [(name: String, filter: Filter)] {
    FilterKind.insertable.compactMap { kind in
        guard let filter = kind.defaultFilter else { return nil }
        return (kind.displayName, filter)
    }
}

/// `hasIntensity` says whether to draw a slider — `.mono` has nothing to vary,
/// and `.lut` / `.chromaKey` are configured by their payload rather than a scalar.
func v1_0_0_filtersWithASlider() -> [FilterKind] {
    FilterKind.allCases.filter(\.hasIntensity)
}

/// And back the other way: what kind is this filter?
func v1_0_0_describe(_ filter: Filter) -> String {
    filter.kind.displayName
}

// MARK: - Chroma key from its own components (v0.22)

/// Rebuild a chroma key from values you stored, without a `PlatformColor` detour.
///
/// `ChromaKey` exposes `color` as `ColorComponents` but, until v0.22, only
/// initialised from a `PlatformColor` — so it could not be reconstructed from
/// its own public properties. The round trip through a platform colour was
/// lossy on macOS for anything outside sRGB.
func v1_0_0_restoreChromaKey(r: Double, g: Double, b: Double, threshold: Double) -> Filter {
    .chromaKey(ChromaKey(color: ColorComponents(r: r, g: g, b: b), threshold: threshold))
}

// MARK: - Waveform resampling (v0.19)

/// Resample a waveform to the number of bars a view actually has.
///
/// Extraction is the expensive half, so do it once at the source resolution and
/// resample per layout — not once per pixel width.
func v1_0_0_waveformForWidth(_ bars: Int) async throws -> [Float] {
    let waveform = try await AudioWaveformLoader.load(
        url: URL(fileURLWithPath: "/tmp/bed.m4a"),
        sampleCount: 2_000
    )
    return waveform.resampled(to: bars).peaks
}

// MARK: - Control flow in the builders (v0.21)

/// Build a composition from a runtime collection.
///
/// `AudioBuilder` had only `buildBlock`, so `.audio { }` took a literal list and
/// nothing else — a caller holding `[AudioTrack]` had no way in, because
/// `audioTracks` is `internal(set)` and the builder was the only public door.
func v1_0_0_fromRuntimeCollections(
    clips: [VideoClip],
    beds: [AudioTrack],
    includeVoiceover: Bool
) -> Video {
    Video {
        for clip in clips { clip }
    }
    .audio {
        for bed in beds { bed }
        if includeVoiceover {
            AudioTrack(url: URL(fileURLWithPath: "/tmp/vo.m4a"))
        }
    }
}

/// The empty composition is a real state — a new project, or one whose last
/// clip was just deleted. Before v0.21 it did not compile.
func v1_0_0_emptyComposition() -> Video {
    Video { }.preset(.reelsAndShorts)
}

// MARK: - Filter identity (v0.21)

/// Re-apply a filter under the identity it was saved with.
///
/// Every other `filter` modifier generates a fresh `FilterID`, which is right
/// for a new filter and wrong for a restored one: it orphans any animation bound
/// with `filterAnimation(for:)` and drops any selection keyed to it.
func v1_0_0_restoreFilters(
    on clip: VideoClip,
    saved: [(filter: Filter, id: FilterID)]
) -> VideoClip {
    saved.reduce(clip) { partial, entry in
        partial.filter(entry.filter, id: entry.id)
    }
}

// MARK: - Preset equality (v0.21)

/// `Preset` is `Equatable`, so a settings screen can compare without a switch.
func v1_0_0_isVertical(_ preset: Preset) -> Bool {
    preset == .reelsAndShorts || preset == .tiktok
}
