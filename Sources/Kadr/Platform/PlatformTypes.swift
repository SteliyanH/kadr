// PlatformTypes.swift — Cross-platform type aliases

#if canImport(UIKit)
import UIKit
/// Cross-platform image alias — `UIImage` on UIKit platforms, `NSImage` on AppKit.
public typealias PlatformImage = UIImage
/// Cross-platform color alias — `UIColor` on UIKit platforms, `NSColor` on AppKit.
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
/// Cross-platform image alias — `UIImage` on UIKit platforms, `NSImage` on AppKit.
public typealias PlatformImage = NSImage
/// Cross-platform color alias — `UIColor` on UIKit platforms, `NSColor` on AppKit.
public typealias PlatformColor = NSColor
#endif
