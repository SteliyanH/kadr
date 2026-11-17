import Foundation
import Kadr

// The names the README snippets use. They point at the media ReadmeArt draws,
// so the same snippets that CI compiles are the ones `swift run
// KadrReadmeMedia` runs to render the README's GIFs. For compiling alone, the
// files do not need to exist.
//
// Images are computed rather than stored: a stored global of `PlatformImage`
// would be shared mutable state as far as Swift 6 is concerned.

var coast: PlatformImage { ReadmeArt.scene(0) }
var mountains: PlatformImage { ReadmeArt.scene(1) }
var dusk: PlatformImage { ReadmeArt.scene(2) }
var lake: PlatformImage { ReadmeArt.scene(3) }

let droneURL = ReadmeArt.url("drone.mov")
let reactionURL = ReadmeArt.url("reaction.mov")
let presenterURL = ReadmeArt.url("presenter.mov")
let rollURL = ReadmeArt.url("roll.mov")
let musicURL = ReadmeArt.url("music.wav")
let outputURL = ReadmeArt.url("out.mp4")
