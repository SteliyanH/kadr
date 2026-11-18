import Foundation
import Kadr

// The names the DocC articles' snippets use, so Tools/readme-snippets.sh can
// compile them. Nothing here is rendered or run, so the files need not exist.
//
// `fade` and `ramp` are defined by an earlier snippet in KeyframeAnimation.md
// and used by later ones; these stand in for them.

let url = URL(fileURLWithPath: "/tmp/clip.mov")
let clipURL = url
let main = URL(fileURLWithPath: "/tmp/main.mov")
let inset = URL(fileURLWithPath: "/tmp/inset.mov")
let a = URL(fileURLWithPath: "/tmp/a.mov")
let b = URL(fileURLWithPath: "/tmp/b.mov")
let lutURL = URL(fileURLWithPath: "/tmp/grade.cube")

var heroImage: PlatformImage { ReadmeArt.scene(0) }
var first: PlatformImage { ReadmeArt.scene(0) }
var second: PlatformImage { ReadmeArt.scene(1) }
var third: PlatformImage { ReadmeArt.scene(2) }
var photo: PlatformImage { ReadmeArt.scene(3) }
var beach: PlatformImage { ReadmeArt.scene(0) }
var logo: PlatformImage { ReadmeArt.scene(1) }

var clip: VideoClip { VideoClip(url: url) }
var video: Video { Video { clip } }
var slideshow: Video { Video { ImageClip(first, duration: 3.0) } }

let fade = Animation<Double>.keyframes([.at(0.0, value: 0.0), .at(1.0, value: 1.0)])
let ramp = Animation<Double>.keyframes([.at(0.0, value: 0.0), .at(2.0, value: 0.6)])
