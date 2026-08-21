# Benchmarks

Export-path benchmarks for the three scenarios the v1.0 roadmap names:
single-track export, multi-track with `KadrVideoCompositor`, and keyframe-heavy
compositions.

## Why this exists

v0.13 was an entire performance cycle claiming a **10–30% export improvement**.
Nothing in this repository could verify that number, and nothing could catch it
regressing — the claim rested on profiled traces taken once, by hand, on one
machine. This makes the claim checkable and a regression visible.

## Why it is not in CI

Export needs hardware encode. The hosted runners are virtual machines without
it, which is the same reason `KADR_SKIP_REENCODE_TESTS` exists. Run these
locally before and after a performance change, or from the nightly hardware job.

## Usage

```sh
# Always release. A debug build measures the absence of the optimiser.
swift run -c release KadrBenchmarks

# Record a baseline before a change, compare after it.
swift run -c release KadrBenchmarks --json > before.json
#   ...make the change...
swift run -c release KadrBenchmarks --compare before.json   # exit 1 if slower
```

`--compare` tolerates 10% by default (`--tolerance`), because a laptop cannot
measure closer than that reliably. It exits non-zero on a real regression, which
is what makes it usable from a script.

## Reading the output

The headline figure is the **minimum**, not the mean. A mean over a small sample
on a working machine measures background noise as much as it measures the code;
the fastest run is the one least polluted. Spread is printed alongside, and a
run whose slowest sample strays more than 25% from its fastest is flagged
`⚠︎ noisy` — treat those numbers as unusable rather than merely imprecise.

## The fixtures are synthetic, deliberately

Compositions are built from solid-colour images rather than sample footage. A
benchmark that decodes a real asset measures the decoder — which is hardware,
varies by machine, and is the one part of this pipeline the package does not
implement. Synthetic sources keep the measurement on the code under test.

## A finding from the first run

On an M-series laptop, the keyframe-heavy scenario (120 keyframes over 5s) runs
within a few percent of the single-track baseline. **Keyframe evaluation is not
a meaningful cost at that density** — the export is dominated by encode. Worth
knowing before optimising the sampler: the roadmap names this scenario, but the
first measurement suggests the multi-track compositor path is where the time
actually goes, at roughly 3× the single-track figure.
