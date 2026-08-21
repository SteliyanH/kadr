# Examples

Self-contained recipes, one file per release cycle. URLs are placeholders —
point them at real assets to run anything.

## These compile

`Examples` is a build target, not a folder of loose files. That is a change: it
used to be reference material nothing checked, and it had rotted —
`V080Showcase.swift` passed `Transform`'s arguments in an order the initialiser
no longer accepted, and two showcases each declared a `MultiplyBlend` that only
collided once anything tried to build them together.

Examples that do not compile are worse than no examples: they teach an API that
does not exist, and they fail at the moment someone is deciding whether to trust
the package. Compiling them means an API change breaks the build here rather
than breaking a newcomer's first afternoon.

## What is where

| File | Cycle |
|---|---|
| `V020Showcase.swift` … `V080Showcase.swift` | earlier cycles |
| `V090Showcase.swift` | speed curves, pitch-preserving audio speed, captions |
| `V100Showcase.swift` | track opacity, clearing animations |
| `V110Showcase.swift` | keyed filters by `FilterID` |
| `V120Showcase.swift` | text stroke and shadow |
| `V140Showcase.swift` | `ThumbnailGenerator` |
| `APIValidation.swift` | surface coverage |
| `SimpleEditor/` | a small end-to-end app |

There is no `V130Showcase`: v0.13 was a pure performance cycle with no public
surface to demonstrate. Its work is measurable in `Benchmarks/`, not readable
here.
