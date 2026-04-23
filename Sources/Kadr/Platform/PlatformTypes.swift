// PlatformTypes.swift — Cross-platform type aliases

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
#endif
